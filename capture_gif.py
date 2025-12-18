"""
Script to capture HTML animation and convert to GIF
"""
import time
import os
from PIL import Image
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from webdriver_manager.chrome import ChromeDriverManager

def capture_html_to_gif(html_url, output_gif, duration=5, fps=10):
    """
    Capture an animated HTML page and save as GIF
    
    Args:
        html_url: URL of the HTML page
        output_gif: Output GIF file path
        duration: Duration to capture in seconds
        fps: Frames per second
    """
    # Setup Chrome options
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--window-size=1600,1000")
    chrome_options.add_argument("--hide-scrollbars")
    chrome_options.add_argument("--disable-gpu")
    chrome_options.add_argument("--no-sandbox")
    
    print("Starting Chrome browser...")
    driver = webdriver.Chrome(
        service=Service(ChromeDriverManager().install()),
        options=chrome_options
    )
    
    try:
        print(f"Loading page: {html_url}")
        driver.get(html_url)
        
        # Wait for initial animations to start
        time.sleep(2)
        
        frames = []
        frame_count = duration * fps
        frame_interval = 1.0 / fps
        
        print(f"Capturing {frame_count} frames at {fps} FPS...")
        
        for i in range(frame_count):
            # Take screenshot
            screenshot = driver.get_screenshot_as_png()
            
            # Convert to PIL Image
            from io import BytesIO
            img = Image.open(BytesIO(screenshot))
            
            # Convert to RGB (GIF doesn't support RGBA well)
            if img.mode == 'RGBA':
                # Create white background
                background = Image.new('RGB', img.size, (255, 255, 255))
                background.paste(img, mask=img.split()[3])
                img = background
            elif img.mode != 'RGB':
                img = img.convert('RGB')
            
            # Reduce size for smaller GIF
            img = img.resize((1200, 750), Image.Resampling.LANCZOS)
            
            frames.append(img)
            
            # Progress indicator
            if (i + 1) % 10 == 0:
                print(f"  Captured frame {i + 1}/{frame_count}")
            
            time.sleep(frame_interval)
        
        print(f"Saving GIF to {output_gif}...")
        
        # Save as GIF
        frames[0].save(
            output_gif,
            save_all=True,
            append_images=frames[1:],
            duration=int(1000 / fps),  # Duration per frame in ms
            loop=0,  # Loop forever
            optimize=True
        )
        
        # Get file size
        size_mb = os.path.getsize(output_gif) / (1024 * 1024)
        print(f"✅ GIF created successfully!")
        print(f"   File: {output_gif}")
        print(f"   Size: {size_mb:.2f} MB")
        print(f"   Frames: {len(frames)}")
        print(f"   Duration: {duration} seconds")
        
    finally:
        driver.quit()
        print("Browser closed.")

if __name__ == "__main__":
    # Configuration
    HTML_URL = "http://localhost:8000/architecture.html"
    OUTPUT_GIF = r"E:\DevOps practice projects\Project 8\netflix-oss-project\architecture.gif"
    DURATION = 6  # seconds
    FPS = 8  # frames per second
    
    capture_html_to_gif(HTML_URL, OUTPUT_GIF, DURATION, FPS)
