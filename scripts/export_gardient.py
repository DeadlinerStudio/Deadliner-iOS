import json
import os
import argparse
from PIL import Image, ImageDraw

def parse_color(color_str):
    """
    解析苹果的颜色字符串，例如 "display-p3:0.63958,0.71204,0.86066,1.00000"
    将 0~1 的浮点数粗略转换为 0~255 的 RGBA 值
    """
    # 提取冒号后面的数值部分
    if ':' in color_str:
        color_data = color_str.split(':')[1]
    else:
        color_data = color_str
        
    r, g, b, a = [float(v) for v in color_data.split(',')]
    
    # 将 P3 色域的值简单映射到 0-255 (对于常规预览已足够准确)
    return (int(r * 255), int(g * 255), int(b * 255), int(a * 255))

def generate_gradient_bg(icon_bundle_path, output_path, base_size=(1024, 1024)):
    json_path = os.path.join(icon_bundle_path, "icon.json")
    
    if not os.path.exists(json_path):
        print(f"❌ 错误: 在包内找不到 {json_path}")
        return

    print(f"📂 正在读取渐变配置: {json_path}")
    
    with open(json_path, 'r', encoding='utf-8') as f:
        config = json.load(f)
        
    # 查找 fill-specializations 中的线性渐变配置
    gradient_config = None
    for spec in config.get('fill-specializations', []):
        value = spec.get('value', {})
        if isinstance(value, dict) and 'linear-gradient' in value:
            gradient_config = value
            break
            
    if not gradient_config:
        print("❌ 错误: JSON 中没有找到 linear-gradient 配置。")
        return
        
    # 获取颜色和坐标
    colors = gradient_config.get('linear-gradient')
    start_color = parse_color(colors[0])
    stop_color = parse_color(colors[1])
    
    orientation = gradient_config.get('orientation', {})
    start_point = orientation.get('start', {})
    stop_point = orientation.get('stop', {})
    
    # 创建画布
    canvas = Image.new("RGBA", base_size)
    draw = ImageDraw.Draw(canvas)
    width, height = base_size
    
    # 计算实际像素高度的起止点
    y_start_px = height * start_point.get('y', 1.0)
    y_stop_px = height * stop_point.get('y', 0.0)
    
    # 逐行绘制渐变 (因为 x 固定为 0.5，这里只做垂直渐变)
    for y in range(height):
        # 计算插值比例 t (从 0 到 1)
        if y_start_px != y_stop_px:
            t = (y - y_start_px) / (y_stop_px - y_start_px)
        else:
            t = 0
            
        # 限制 t 的范围在 0~1 之间，超出起止点的部分将使用纯色填充
        t = max(0.0, min(1.0, t))
        
        # 线性插值计算当前行的颜色
        r = int(start_color[0] + (stop_color[0] - start_color[0]) * t)
        g = int(start_color[1] + (stop_color[1] - start_color[1]) * t)
        b = int(start_color[2] + (stop_color[2] - start_color[2]) * t)
        a = int(start_color[3] + (stop_color[3] - start_color[3]) * t)
        
        # 绘制当前行
        draw.line([(0, y), (width, y)], fill=(r, g, b, a))

    # 保存图片
    canvas.save(output_path)
    print(f"🎉 渐变背景已生成并保存至: {output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="从苹果 .icon 文件提取并生成渐变背景")
    parser.add_argument("input", help="输入的 .icon 文件夹路径")
    parser.add_argument("-o", "--output", default="gradient_bg.png", help="输出的图片文件路径 (默认: gradient_bg.png)")
    
    args = parser.parse_args()
    generate_gradient_bg(args.input, args.output)