#!/usr/bin/env python3
# patch_lottie_matte.py

import argparse
import json
from pathlib import Path
from copy import deepcopy


TARGET_LAYER_INDICES = [160, 165]


def make_matte_layer(
    ind: int,
    parent: int = 10,
    center_x: float = 106,
    center_y: float = 220.5,
    width: float = 212,
    height: float = 441,
    radius: float = 34,
    ip: int = 0,
    op: int = 241,
    st: int = 0,
) -> dict:
    return {
        "ind": ind,
        "ty": 4,
        "parent": parent,
        "td": 1,
        "ks": {},
        "ip": ip,
        "op": op,
        "st": st,
        "shapes": [
            {
                "ty": "rc",
                "p": {"a": 0, "k": [center_x, center_y]},
                "r": {"a": 0, "k": radius},
                "s": {"a": 0, "k": [width, height]},
            },
            {
                "ty": "fl",
                "c": {"a": 0, "k": [1, 1, 1]},
                "o": {"a": 0, "k": 100},
            },
        ],
    }


def get_layer_indices(layers: list[dict]) -> list[int]:
    return [
        layer.get("ind")
        for layer in layers
        if isinstance(layer, dict) and "ind" in layer
    ]


def find_layer_position(layers: list[dict], ind: int) -> int | None:
    for i, layer in enumerate(layers):
        if isinstance(layer, dict) and layer.get("ind") == ind:
            return i
    return None


def describe_matte_layer(layer: dict) -> str:
    shape = layer.get("shapes", [{}])[0]
    return (
        f'ind={layer.get("ind")}, '
        f'parent={layer.get("parent")}, '
        f'td={layer.get("td")}, '
        f'center={shape.get("p", {}).get("k")}, '
        f'size={shape.get("s", {}).get("k")}, '
        f'radius={shape.get("r", {}).get("k")}'
    )


def validate_patch(data: dict, verbose: bool = True) -> bool:
    layers = data.get("layers")
    if not isinstance(layers, list):
        if verbose:
            print("[FAIL] root 'layers' 不存在或不是 list")
        return False

    ok = True

    checks = [
        (9001, 160),
        (9002, 165),
    ]

    for matte_ind, target_ind in checks:
        matte_pos = find_layer_position(layers, matte_ind)
        target_pos = find_layer_position(layers, target_ind)

        if matte_pos is None:
            print(f"[FAIL] 没找到 matte layer ind={matte_ind}")
            ok = False
            continue

        if target_pos is None:
            print(f"[FAIL] 没找到 target layer ind={target_ind}")
            ok = False
            continue

        matte_layer = layers[matte_pos]
        target_layer = layers[target_pos]

        print(f"[INFO] matte layer: {describe_matte_layer(matte_layer)}")
        print(
            f"[INFO] target layer: ind={target_ind}, "
            f"tt={target_layer.get('tt')}, "
            f"parent={target_layer.get('parent')}, "
            f"refId={target_layer.get('refId')}"
        )

        if matte_pos + 1 != target_pos:
            print(
                f"[FAIL] ind={matte_ind} 没有紧贴在 ind={target_ind} 前面："
                f"matte_pos={matte_pos}, target_pos={target_pos}"
            )
            ok = False
        else:
            print(f"[OK] ind={matte_ind} 正确插在 ind={target_ind} 前一位")

        if matte_layer.get("td") != 1:
            print(f"[FAIL] matte ind={matte_ind} 缺少 td=1")
            ok = False
        else:
            print(f"[OK] matte ind={matte_ind} 有 td=1")

        if target_layer.get("tt") != 1:
            print(f"[FAIL] target ind={target_ind} 缺少 tt=1")
            ok = False
        else:
            print(f"[OK] target ind={target_ind} 有 tt=1")

    if ok:
        print("[OK] Patch 结构检查通过")
    else:
        print("[FAIL] Patch 结构检查未通过")

    return ok


def patch_lottie(
    data: dict,
    crop_width: float,
    crop_height: float,
    crop_radius: float,
    crop_center_x: float,
    crop_center_y: float,
    parent: int,
) -> dict:
    patched = deepcopy(data)

    layers = patched.get("layers")
    if not isinstance(layers, list):
        raise ValueError("Invalid Lottie JSON: root 'layers' is missing or not a list.")

    existing_indices = {
        layer.get("ind")
        for layer in layers
        if isinstance(layer, dict)
    }

    if 9001 in existing_indices or 9002 in existing_indices:
        raise ValueError("This file seems already patched: layer ind 9001 or 9002 already exists.")

    found_targets = {
        layer.get("ind")
        for layer in layers
        if isinstance(layer, dict) and layer.get("ind") in TARGET_LAYER_INDICES
    }

    missing = set(TARGET_LAYER_INDICES) - found_targets
    if missing:
        raise ValueError(f"Target layers not found before patch: {sorted(missing)}")

    matte_map = {
        160: 9001,
        165: 9002,
    }

    new_layers = []

    for layer in layers:
        if not isinstance(layer, dict):
            new_layers.append(layer)
            continue

        layer_ind = layer.get("ind")

        if layer_ind in TARGET_LAYER_INDICES:
            matte_ind = matte_map[layer_ind]

            matte_layer = make_matte_layer(
                ind=matte_ind,
                parent=parent,
                center_x=crop_center_x,
                center_y=crop_center_y,
                width=crop_width,
                height=crop_height,
                radius=crop_radius,
                ip=layer.get("ip", 0),
                op=layer.get("op", patched.get("op", 240)),
                st=layer.get("st", 0),
            )

            new_layers.append(matte_layer)

            patched_layer = deepcopy(layer)
            patched_layer["tt"] = 1
            new_layers.append(patched_layer)
        else:
            new_layers.append(layer)

    patched["layers"] = new_layers
    return patched


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Patch Jitter-exported Lottie JSON by adding alpha mattes to phone content layers."
    )
    parser.add_argument("input", type=Path, help="Input Lottie JSON file.")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="Output Lottie JSON file. Default: <input>.patched.json",
    )

    parser.add_argument("--width", type=float, default=212, help="Crop mask width. Default: 212")
    parser.add_argument("--height", type=float, default=441, help="Crop mask height. Default: 441")
    parser.add_argument("--radius", type=float, default=34, help="Crop mask corner radius. Default: 34")
    parser.add_argument("--center-x", type=float, default=106, help="Crop mask center x. Default: 106")
    parser.add_argument("--center-y", type=float, default=220.5, help="Crop mask center y. Default: 220.5")
    parser.add_argument("--parent", type=int, default=10, help="Mask parent layer index. Default: 10")

    args = parser.parse_args()

    input_path = args.input
    output_path = args.output or input_path.with_name(f"{input_path.stem}.patched{input_path.suffix}")

    print(f"[INFO] Input:  {input_path}")
    print(f"[INFO] Output: {output_path}")
    print(
        "[INFO] Crop: "
        f"center=({args.center_x}, {args.center_y}), "
        f"size=({args.width}, {args.height}), "
        f"radius={args.radius}, parent={args.parent}"
    )

    with input_path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    layers = data.get("layers")
    if not isinstance(layers, list):
        raise ValueError("Invalid Lottie JSON: root 'layers' is missing or not a list.")

    before_count = len(layers)
    before_indices = get_layer_indices(layers)

    print(f"[INFO] Root layer count before: {before_count}")
    print(f"[INFO] Has target 160: {160 in before_indices}")
    print(f"[INFO] Has target 165: {165 in before_indices}")
    print(f"[INFO] Already has 9001: {9001 in before_indices}")
    print(f"[INFO] Already has 9002: {9002 in before_indices}")

    patched = patch_lottie(
        data=data,
        crop_width=args.width,
        crop_height=args.height,
        crop_radius=args.radius,
        crop_center_x=args.center_x,
        crop_center_y=args.center_y,
        parent=args.parent,
    )

    patched_layers = patched.get("layers", [])
    after_count = len(patched_layers)

    print(f"[INFO] Root layer count after:  {after_count}")
    print(f"[INFO] Expected layer count:    {before_count + 2}")

    if after_count == before_count + 2:
        print("[OK] 新增了 2 个 matte layer")
    else:
        print("[FAIL] layer 数量不符合预期")

    print("[INFO] Running structural validation...")
    is_valid = validate_patch(patched)

    if not is_valid:
        raise RuntimeError("Patch validation failed. Output file was not written.")

    with output_path.open("w", encoding="utf-8") as f:
        json.dump(patched, f, ensure_ascii=False, separators=(",", ":"))

    print(f"[OK] Patched Lottie saved to: {output_path}")


if __name__ == "__main__":
    main()