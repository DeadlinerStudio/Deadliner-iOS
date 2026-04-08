import json
import os
import argparse
from PIL import Image

def generate_icon_from_bundle(icon_bundle_path, output_path, base_size=(1024, 1024)):
    """
    读取苹果的 .icon 包文件夹，忽略所有特效并使用正确的 Alpha 通道合成最终图标
    """
    json_path = os.path.join(icon_bundle_path, "icon.json")
    assets_dir = os.path.join(icon_bundle_path, "Assets")
    
    if not os.path.isdir(icon_bundle_path):
        print(f"❌ 错误: 找不到图标包 {icon_bundle_path}")
        return
    if not os.path.exists(json_path):
        print(f"❌ 错误: 在包内找不到 {json_path}")
        return

    print(f"📂 正在解析图标包: {icon_bundle_path}")
    
    with open(json_path, 'r', encoding='utf-8') as f:
        config = json.load(f)
    
    # 创建透明背景的主画布
    canvas = Image.new("RGBA", base_size, (0, 0, 0, 0))
    groups = config.get('groups', [])
    
    # 逆序遍历，确保背景先画
    for group in reversed(groups):
        layers = group.get('layers', [])
        
        for layer in reversed(layers):
            image_name = layer.get('image-name')
            if not image_name:
                continue
                
            image_path = os.path.join(assets_dir, image_name)
            
            if not os.path.exists(image_path):
                print(f"⚠️ 找不到图片: {image_name}，跳过。")
                continue
                
            layer_img = Image.open(image_path).convert("RGBA")
            
            position = layer.get('position', {})
            scale = position.get('scale', 1.0)
            translation = position.get('translation-in-points', [0, 0])
            trans_x, trans_y = translation[0], translation[1]
            
            # 缩放处理
            if scale != 1.0:
                new_w = int(layer_img.width * scale)
                new_h = int(layer_img.height * scale)
                layer_img = layer_img.resize((new_w, new_h), Image.Resampling.LANCZOS)
            
            # 位移计算
            offset_x = (base_size[0] - layer_img.width) // 2 + int(trans_x)
            offset_y = (base_size[1] - layer_img.height) // 2 - int(trans_y)
            
            # ---------------------------------------------------------
            # 修复脏边/发黑问题的核心代码：
            # 1. 创建一个与主画布等大的全透明临时图层
            temp_layer = Image.new("RGBA", base_size, (0, 0, 0, 0))
            # 2. 将当前图层按坐标放置在临时图层上
            temp_layer.paste(layer_img, (offset_x, offset_y))
            # 3. 使用 alpha_composite 进行标准的光学透明度混合
            canvas = Image.alpha_composite(canvas, temp_layer)
            # ---------------------------------------------------------
            
            print(f"✅ 已贴入图层: {layer.get('name', image_name)}")

    canvas.save(output_path)
    print(f"\n🎉 搞定！合成图标已保存至: {output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="从苹果 .icon 文件包合成图标")
    parser.add_argument("input", help="输入的 .icon 文件夹路径")
    parser.add_argument("-o", "--output", default="output.png", help="输出的图片文件路径 (默认: output.png)")
    
    args = parser.parse_args()
    generate_icon_from_bundle(args.input, args.output)