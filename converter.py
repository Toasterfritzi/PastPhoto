import os
import subprocess
import uuid
import imageio_ffmpeg

def get_ffmpeg_exe():
    return imageio_ffmpeg.get_ffmpeg_exe()

def process_video(input_path, output_dir, experimental):
    """
    Konvertiert ein Video in die Komponenten eines Live Photos.
    Gibt ein Tuple (jpeg_path, mov_path) zurück.
    """
    ffmpeg_exe = get_ffmpeg_exe()
    
    # Generate common UUID for both files
    content_identifier = str(uuid.uuid4()).upper()
    
    # Define output file paths
    base_name = f"IMG_{content_identifier[:8]}"
    mov_path = os.path.join(output_dir, f"{base_name}.mov")
    jpg_path = os.path.join(output_dir, f"{base_name}.jpg")
    
    # 1. Video zuschneiden / umwandeln in MOV
    # Wenn nicht experimentell, auf 2.5 Sekunden begrenzen.
    ffmpeg_cmd = [
        ffmpeg_exe,
        "-i", input_path,
        "-c:v", "libx264",     # h264 for compatibility
        "-pix_fmt", "yuv420p",
        "-c:a", "aac",
        "-b:a", "128k"
    ]
    
    if not experimental:
        # Begrenze auf 2.5 Sekunden
        ffmpeg_cmd.extend(["-t", "2.5"])
        
    ffmpeg_cmd.extend(["-y", mov_path]) # -y overwrites
    
    print(f"Running FFmpeg to create MOV: {' '.join(ffmpeg_cmd)}")
    subprocess.run(ffmpeg_cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    
    # 2. Key Photo (Standbild) extrahieren
    # Extrahiere ein Frame bei 50% der Videodauer (oder einfach das erste Frame bei Sekunde 0.5)
    ffmpeg_img_cmd = [
        ffmpeg_exe,
        "-ss", "00:00:00.500", # Extract frame at 0.5s
        "-i", input_path,
        "-vframes", "1",
        "-q:v", "2",           # High quality jpeg
        "-y", jpg_path
    ]
    print(f"Running FFmpeg to create JPEG: {' '.join(ffmpeg_img_cmd)}")
    subprocess.run(ffmpeg_img_cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    
    # 3. Metadaten mit exiftool setzen
    # Hinweis: Dies erfordert, dass exiftool auf dem System installiert ist.
    try:
        # Set QuickTime ContentIdentifier on MOV
        exiftool_mov_cmd = [
            "exiftool",
            f"-QuickTime:ContentIdentifier={content_identifier}",
            "-overwrite_original",
            mov_path
        ]
        subprocess.run(exiftool_mov_cmd, check=True)
        
        # Set Apple MakerNotes ContentIdentifier on JPEG
        # Das kann schwierig sein, wenn keine MakerNotes existieren. Wir versuchen es als XMP.
        exiftool_jpg_cmd = [
            "exiftool",
            f"-Apple:ContentIdentifier={content_identifier}",
            f"-Apple:ImageUniqueID={content_identifier}",
            "-overwrite_original",
            jpg_path
        ]
        # Das könnte fehlschlagen, wenn keine MakerNotes da sind, ignorieren wir Fehler vorerst.
        subprocess.run(exiftool_jpg_cmd, check=False)
        
    except FileNotFoundError:
        print("WARNUNG: exiftool wurde nicht gefunden. Metadaten wurden nicht geschrieben.")
        # Wir werfen hier keinen Fehler, damit die App nicht crasht.

    return (jpg_path, mov_path)
