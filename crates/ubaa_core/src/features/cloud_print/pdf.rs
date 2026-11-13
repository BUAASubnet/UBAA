use std::io::Cursor;

use image::{DynamicImage, ImageDecoder as _, ImageFormat, ImageReader, codecs::jpeg::JpegEncoder};
use lopdf::content::{Content, Operation};
use lopdf::{Document, Object, Stream, dictionary};

use crate::error::{Result, UbaaError};

pub(super) fn image_pdf(bytes: &[u8], paper: i32) -> Result<Vec<u8>> {
    image_pdf_inner(bytes, paper)
        .ok_or_else(|| UbaaError::invalid_input("无法将该图片转为可预览的打印文件"))
}

fn image_pdf_inner(bytes: &[u8], paper: i32) -> Option<Vec<u8>> {
    let mut reader = ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .ok()?;
    let format = reader.format()?;
    if !matches!(format, ImageFormat::Jpeg | ImageFormat::Png) {
        return None;
    }
    let mut limits = image::Limits::default();
    limits.max_alloc = Some(96 * 1024 * 1024);
    limits.max_image_width = Some(12_000);
    limits.max_image_height = Some(12_000);
    reader.limits(limits);
    let mut decoder = reader.into_decoder().ok()?;
    let (width, height) = decoder.dimensions();
    if u64::from(width) * u64::from(height) > 24_000_000 {
        return None;
    }
    let orientation = decoder.orientation().ok()?;
    let mut photo = DynamicImage::from_decoder(decoder).ok()?;
    photo.apply_orientation(orientation);
    let (width, height) = (photo.width(), photo.height());
    if width == 0 || height == 0 {
        return None;
    }

    let mut attributes = dictionary! {
        "Type" => "XObject", "Subtype" => "Image", "ColorSpace" => "DeviceRGB",
        "Width" => width, "Height" => height, "BitsPerComponent" => 8,
    };
    let image = if format == ImageFormat::Jpeg {
        let mut jpeg = Vec::new();
        JpegEncoder::new_with_quality(&mut jpeg, 94)
            .encode_image(&photo.into_rgb8())
            .ok()?;
        attributes.set("Filter", Object::Name(b"DCTDecode".to_vec()));
        Stream::new(attributes, jpeg)
    } else {
        let rgb = if photo.color().has_alpha() {
            photo
                .into_rgba8()
                .pixels()
                .flat_map(|pixel| {
                    let alpha = u16::from(pixel[3]);
                    [pixel[0], pixel[1], pixel[2]].map(|c| {
                        u8::try_from((u16::from(c) * alpha + 255 * (255 - alpha) + 127) / 255)
                            .expect("合成颜色在八位范围内")
                    })
                })
                .collect()
        } else {
            photo.into_rgb8().into_raw()
        };
        let mut stream = Stream::new(attributes, rgb);
        stream.compress().ok()?;
        stream
    };

    let (mut w, mut h) = if paper == 8 {
        (841.89_f32, 1190.55_f32)
    } else {
        (595.28_f32, 841.89_f32)
    };
    if width > height {
        std::mem::swap(&mut w, &mut h);
    }
    #[allow(clippy::cast_precision_loss)]
    // Dimensions are bounded well within f32's exact integer range.
    let (iw, ih) = (width as f32, height as f32);
    let scale = (w / iw).min(h / ih);
    let (dw, dh) = (iw * scale, ih * scale);
    let content = Content {
        operations: vec![
            Operation::new("q", vec![]),
            Operation::new(
                "cm",
                vec![
                    dw.into(),
                    0.into(),
                    0.into(),
                    dh.into(),
                    ((w - dw) / 2.0).into(),
                    ((h - dh) / 2.0).into(),
                ],
            ),
            Operation::new("Do", vec![Object::Name(b"Image".to_vec())]),
            Operation::new("Q", vec![]),
        ],
    };
    let mut doc = Document::with_version("1.5");
    let pages = doc.new_object_id();
    let image = doc.add_object(image);
    let content = doc.add_object(Stream::new(dictionary! {}, content.encode().ok()?));
    let page = doc.add_object(dictionary! {
        "Type" => "Page", "Parent" => pages, "Contents" => content,
        "MediaBox" => vec![0.into(), 0.into(), w.into(), h.into()],
        "Resources" => dictionary! { "XObject" => dictionary! { "Image" => image } },
    });
    set_root(&mut doc, pages, vec![page.into()], 1);
    let mut output = Vec::new();
    doc.save_to(&mut output).ok()?;
    Some(output)
}

fn set_root(doc: &mut Document, pages: lopdf::ObjectId, kids: Vec<Object>, count: i64) {
    doc.set_object(
        pages,
        dictionary! { "Type" => "Pages", "Kids" => kids, "Count" => count },
    );
    let catalog = doc.add_object(dictionary! { "Type" => "Catalog", "Pages" => pages });
    doc.trailer.set("Root", catalog);
}

pub(crate) fn merge_scan_pdfs(inputs: Vec<Vec<u8>>) -> Result<Vec<u8>> {
    merge(inputs)
        .ok_or_else(|| UbaaError::invalid_input("至少一份扫描件无法作为 PDF 合并，本组未保存"))
}

fn merge(inputs: Vec<Vec<u8>>) -> Option<Vec<u8>> {
    let mut output = Document::with_version("1.7");
    let root = output.new_object_id();
    let mut count = 0_i64;
    let mut children = Vec::with_capacity(inputs.len());
    for input in inputs {
        let mut doc = Document::load_mem(&input).ok()?;
        if doc.is_encrypted() {
            return None;
        }
        if doc.version == "2.0" {
            output.version = doc.version.clone();
        }
        let page_count = i64::try_from(doc.page_iter().count()).ok()?;
        if page_count == 0 {
            return None;
        }
        doc.renumber_objects_with(output.max_id.checked_add(1)?);
        let branch = doc
            .catalog()
            .ok()?
            .get(b"Pages")
            .ok()?
            .as_reference()
            .ok()?;
        let tree = doc.get_object_mut(branch).ok()?.as_dict_mut().ok()?;
        if tree.get(b"Count").ok()?.as_i64().ok()? != page_count {
            return None;
        }
        // Keep the original page tree so inherited resources, dimensions and rotation survive.
        tree.set("Parent", root);
        output.max_id = doc.max_id;
        output.objects.append(&mut doc.objects);
        children.push(branch.into());
        count = count.checked_add(page_count)?;
    }
    if count == 0 {
        return None;
    }
    set_root(&mut output, root, children, count);
    output.prune_objects();
    let mut bytes = Vec::new();
    output.save_to(&mut bytes).ok()?;
    Some(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn source(marker: f32, width: i64) -> Vec<u8> {
        let mut doc = Document::with_version("1.5");
        let pages = doc.new_object_id();
        let stream = doc.add_object(Stream::new(
            dictionary! {},
            format!("{marker} 0 0 rg\n0 0 30 30 re\nf\n").into_bytes(),
        ));
        let page = doc
            .add_object(dictionary! { "Type" => "Page", "Parent" => pages, "Contents" => stream });
        set_root(&mut doc, pages, vec![page.into()], 1);
        let tree = doc.get_object_mut(pages).unwrap().as_dict_mut().unwrap();
        tree.set(
            "MediaBox",
            vec![0.into(), 0.into(), width.into(), 200.into()],
        );
        tree.set("Rotate", 90);
        let mut bytes = Vec::new();
        doc.save_to(&mut bytes).unwrap();
        bytes
    }

    #[test]
    fn cloud_print_merges_in_input_order_with_original_dimensions_and_rotation() {
        let result = merge_scan_pdfs(vec![source(0.8, 170), source(0.2, 130)]).unwrap();
        let pdf = Document::load_mem(&result).unwrap();
        let pages: Vec<_> = pdf.get_pages().into_values().collect();
        assert_eq!(pages.len(), 2);
        for (id, marker, width) in [
            (pages[0], b"0.8".as_slice(), 170),
            (pages[1], b"0.2".as_slice(), 130),
        ] {
            assert!(pdf.get_page_content(id).starts_with(marker));
            let branch = pdf
                .get_dictionary(id)
                .unwrap()
                .get(b"Parent")
                .unwrap()
                .as_reference()
                .unwrap();
            let branch = pdf.get_dictionary(branch).unwrap();
            assert_eq!(
                branch.get(b"MediaBox").unwrap().as_array().unwrap()[2]
                    .as_i64()
                    .unwrap(),
                width
            );
            assert_eq!(branch.get(b"Rotate").unwrap().as_i64().unwrap(), 90);
        }
        assert!(merge_scan_pdfs(vec![source(0.8, 170), b"not a pdf".to_vec()]).is_err());
    }

    #[test]
    fn cloud_print_wraps_png_and_jpeg_in_a_single_page_matching_paper_orientation() {
        let image =
            DynamicImage::ImageRgb8(image::RgbImage::from_pixel(8, 4, image::Rgb([30, 80, 220])));
        for format in [ImageFormat::Jpeg, ImageFormat::Png] {
            let mut bytes = Cursor::new(Vec::new());
            image.write_to(&mut bytes, format).unwrap();
            let pdf = Document::load_mem(&image_pdf(bytes.get_ref(), 8).unwrap()).unwrap();
            let pages = pdf.get_pages();
            assert_eq!(pages.len(), 1);
            let page = pdf.get_dictionary(pages[&1]).unwrap();
            let box_ = page.get(b"MediaBox").unwrap().as_array().unwrap();
            assert!(box_[2].as_float().unwrap() > 1190.0);
            assert!(box_[3].as_float().unwrap() > 841.0 && box_[3].as_float().unwrap() < 842.0);
            assert_eq!(pdf.get_page_images(pages[&1]).unwrap().len(), 1);
        }
    }
}
