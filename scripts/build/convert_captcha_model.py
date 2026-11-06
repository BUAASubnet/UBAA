#!/usr/bin/env python3
"""将 ddddocr 1.6.1 的默认模型转换为应用使用的标准 ONNX 模型。"""

from __future__ import annotations

import argparse
import gzip
import importlib.metadata
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True, help="模型与字符集输出目录")
    args = parser.parse_args()

    import ddddocr
    import numpy as np
    import onnx
    from onnx import TensorProto, helper, numpy_helper

    if importlib.metadata.version("ddddocr") != "1.6.1":
        raise SystemExit("转换需要 ddddocr==1.6.1")
    if importlib.metadata.version("onnx") != "1.23.2":
        raise SystemExit("转换需要 onnx==1.23.2")
    source = Path(ddddocr.__file__).parent / "common_old.onnx"
    model = onnx.load(source)
    initial = {item.name: numpy_helper.to_array(item) for item in model.graph.initializer}
    replacements = 0
    for node in model.graph.node:
        if node.op_type != "DynamicQuantizeLSTM" or node.domain != "com.microsoft":
            continue
        for weight_index, scale_index, zero_index in ((1, 8, 9), (2, 10, 11)):
            weight = initial[node.input[weight_index]].astype(np.float32)
            scale = initial[node.input[scale_index]].reshape(-1, 1, 1)
            zero = initial[node.input[zero_index]].reshape(-1, 1, 1)
            decoded = ((weight - zero) * scale).transpose(0, 2, 1).copy()
            name = node.input[weight_index] + "_float"
            model.graph.initializer.append(numpy_helper.from_array(decoded, name))
            node.input[weight_index] = name
        del node.input[8:]
        node.op_type = "LSTM"
        node.domain = ""
        replacements += 1
    if replacements != 1:
        raise SystemExit("默认模型的量化 LSTM 数量与已验证来源不一致")
    used = {name for node in model.graph.node for name in node.input}
    retained = [item for item in model.graph.initializer if item.name in used]
    del model.graph.initializer[:]
    model.graph.initializer.extend(retained)
    engine = ddddocr.DdddOcr(show_ad=False)
    charset = engine.ocr_engine.get_charset()
    model.graph.output[0].CopyFrom(
        helper.make_tensor_value_info(model.graph.output[0].name, TensorProto.FLOAT, ["seqlen", 1, len(charset)])
    )
    onnx.checker.check_model(model)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "common.onnx.gz").write_bytes(
        gzip.compress(model.SerializeToString(), compresslevel=9, mtime=0)
    )
    (args.output_dir / "charset.json").write_text(json.dumps(charset, ensure_ascii=False), encoding="utf-8")
    print("验证码模型与字符集已写入指定目录")


if __name__ == "__main__":
    main()
