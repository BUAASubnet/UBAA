//! 当前 SSO 图像验证码的离线识别；模型与字符集随应用提供。

use std::io::{Cursor, Read};
use std::sync::OnceLock;

use image::{DynamicImage, Rgb, RgbImage, RgbaImage, imageops};
use tract_onnx::prelude::*;

use crate::domain::CaptchaFrame;

type Model = TypedRunnableModel<TypedModel>;

const INPUT_WIDTH: u32 = 170;
const INPUT_HEIGHT: u32 = 64;
const CLASS_COUNT: usize = 8210;

static MODEL: OnceLock<Option<Model>> = OnceLock::new();
static CHARSET: OnceLock<Option<Vec<String>>> = OnceLock::new();

fn load_model() -> TractResult<Model> {
    let mut bytes = Vec::new();
    flate2::read::GzDecoder::new(include_bytes!("../../assets/captcha/common.onnx.gz").as_slice())
        .read_to_end(&mut bytes)?;
    tract_onnx::onnx()
        .model_for_read(&mut Cursor::new(bytes))?
        .with_input_fact(0, f32::fact([1, 1, 64, 170]).into())?
        .into_optimized()?
        .into_runnable()
}

/// 只返回当前六位图像格式的答案；无法加载模型或识别时交给手动流程。
pub(crate) fn recognize(frame: &CaptchaFrame) -> Option<String> {
    if frame.width == 0 || frame.height == 0 {
        return None;
    }
    let image = RgbaImage::from_raw(frame.width, frame.height, frame.rgba.clone())?;
    let source = DynamicImage::ImageRgba8(image).to_rgb8();
    let mut padded = RgbImage::from_pixel(
        source.width().checked_add(10)?,
        source.height(),
        Rgb([255, 255, 255]),
    );
    imageops::replace(&mut padded, &source, 5, 0);
    let scaled = imageops::resize(
        &padded,
        INPUT_WIDTH,
        INPUT_HEIGHT,
        imageops::FilterType::Lanczos3,
    );
    let gray = DynamicImage::ImageRgb8(scaled).to_luma8();
    let values: Vec<f32> = gray
        .as_raw()
        .iter()
        .map(|value| f32::from(*value) / 255.0)
        .collect();
    let input = Tensor::from_shape(&[1, 1, 64, 170], &values).ok()?;
    let model = MODEL.get_or_init(|| load_model().ok()).as_ref()?;
    let charset = CHARSET
        .get_or_init(|| {
            serde_json::from_slice(include_bytes!("../../assets/captcha/charset.json")).ok()
        })
        .as_ref()?;
    let output = model.run(tvec!(input.into())).ok()?;
    let logits = output.first()?.to_array_view::<f32>().ok()?;
    if logits.shape().last().copied()? != CLASS_COUNT || charset.len() != CLASS_COUNT {
        return None;
    }
    let mut previous = usize::MAX;
    let mut answer = String::new();
    for scores in logits.as_slice()?.chunks_exact(CLASS_COUNT) {
        let index = scores
            .iter()
            .enumerate()
            .max_by(|left, right| left.1.total_cmp(right.1))?
            .0;
        if index != previous && index != 0 {
            answer.push_str(charset.get(index)?);
        }
        previous = index;
    }
    let answer = answer.to_ascii_lowercase();
    (answer.len() == 6 && answer.bytes().all(|value| value.is_ascii_alphanumeric()))
        .then_some(answer)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 内置模型识别已知文字的合成图片() {
        let image = image::load_from_memory(include_bytes!(
            "../../../../fixtures/auth/captcha_synthetic.png"
        ))
        .unwrap()
        .into_rgba8();
        let frame = CaptchaFrame {
            width: image.width(),
            height: image.height(),
            rgba: image.into_raw(),
        };
        assert_eq!(recognize(&frame).as_deref(), Some("a2b3c4"));
    }
}
