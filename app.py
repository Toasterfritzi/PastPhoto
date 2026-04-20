import os
import uuid
from flask import Flask, request, jsonify, render_template, send_file
from werkzeug.utils import secure_filename
from converter import process_video

app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = os.path.join(os.path.dirname(__file__), 'uploads')
app.config['OUTPUT_FOLDER'] = os.path.join(os.path.dirname(__file__), 'outputs')
app.config['MAX_CONTENT_LENGTH'] = 100 * 1024 * 1024  # 100 MB max

# Ensure directories exist
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
os.makedirs(app.config['OUTPUT_FOLDER'], exist_ok=True)

ALLOWED_EXTENSIONS = {'mp4', 'mov', 'avi', 'mkv'}

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'video' not in request.files:
        return jsonify({'error': 'No video part'}), 400
    
    file = request.files['video']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400
        
    experimental = request.form.get('experimental') == 'true'
    
    if file and allowed_file(file.filename):
        filename = secure_filename(file.filename)
        job_id = str(uuid.uuid4())
        
        # Create job specific folders
        job_dir = os.path.join(app.config['UPLOAD_FOLDER'], job_id)
        os.makedirs(job_dir, exist_ok=True)
        
        input_path = os.path.join(job_dir, filename)
        file.save(input_path)
        
        try:
            # Process the video
            output_dir = os.path.join(app.config['OUTPUT_FOLDER'], job_id)
            os.makedirs(output_dir, exist_ok=True)
            
            result_files = process_video(input_path, output_dir, experimental)
            
            # For now, we just return success and the job id. 
            # Later we will handle the actual download format for iPad.
            return jsonify({
                'success': True, 
                'job_id': job_id,
                'message': 'Konvertierung erfolgreich abgeschlossen!'
            })
            
        except Exception as e:
            return jsonify({'error': str(e)}), 500
            
    return jsonify({'error': 'Invalid file type'}), 400

if __name__ == '__main__':
    app.run(debug=True, port=5000)
