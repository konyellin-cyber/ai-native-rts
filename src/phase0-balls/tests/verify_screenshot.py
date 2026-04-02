#!/usr/bin/env python3
"""
Verify that screenshot PNG matches JSON coordinates.
Samples pixels at ball positions to check for red color (Line2D circles).
"""
import json
from PIL import Image
import sys

def verify_frame(base_path: str, frame_num: int) -> bool:
    img = Image.open(f"{base_path}/screenshots/frame_{frame_num:06d}.png")
    with open(f"{base_path}/frames/frame_{frame_num:06d}.json") as f:
        data = json.load(f)
    
    print(f"\n=== Frame {frame_num} (image: {img.size[0]}x{img.size[1]}) ===")
    
    all_pass = True
    for ball in data["balls"]:
        bid = ball["id"]
        # Round to integer for pixel sampling
        px = int(round(ball["pos_x"]))
        py = int(round(ball["pos_y"]))
        radius = int(ball.get("radius", 20))
        
        # Check multiple points: center + edge offsets
        offsets = [
            (0, 0),           # center
            (radius, 0),      # right edge
            (-radius, 0),     # left edge
            (0, radius),      # bottom edge
            (0, -radius),     # top edge
        ]
        
        red_detected = False
        for ox, oy in offsets:
            sx = max(0, min(px + ox, img.width - 1))
            sy = max(0, min(py + oy, img.height - 1))
            pixel = img.getpixel((sx, sy))
            
            # Red detection: Line2D uses (255, 0, 0, 1.0) = red
            # Some pixels may be background, but at least one edge should hit the circle
            if len(pixel) >= 3:
                r, g, b = pixel[0], pixel[1], pixel[2]
                if r > 200 and g < 50 and b < 50:  # red-ish
                    red_detected = True
                    break
        
        status = "PASS" if red_detected else "FAIL"
        print(f"  Ball {bid}: pos=({px:4d},{py:4d}) radius={radius} {status}")
        if not red_detected:
            all_pass = False
    
    return all_pass

if __name__ == "__main__":
    base_path = "/Users/konyel/.agent/.openclaw/workspace/memory/projects/ai-native-rts/src/phase0-balls"
    frames = [100, 200, 300]
    
    results = []
    for frame_num in frames:
        results.append(verify_frame(base_path, frame_num))
    
    print(f"\n=== Summary ===")
    if all(results):
        print("ALL PASS: Screenshots match JSON coordinates")
        sys.exit(0)
    else:
        print("FAIL: Some balls not detected at expected positions")
        sys.exit(1)
