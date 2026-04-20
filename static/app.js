document.addEventListener('DOMContentLoaded', () => {
    const dropZone = document.getElementById('drop-zone');
    const fileInput = document.getElementById('file-input');
    const experimentalToggle = document.getElementById('experimental-toggle');
    const progressContainer = document.getElementById('upload-progress');
    const progressBar = document.getElementById('progress-bar');
    const progressText = document.getElementById('progress-text');
    const resultContainer = document.getElementById('result-container');

    // Drag and Drop Events
    ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
        dropZone.addEventListener(eventName, preventDefaults, false);
    });

    function preventDefaults(e) {
        e.preventDefault();
        e.stopPropagation();
    }

    ['dragenter', 'dragover'].forEach(eventName => {
        dropZone.addEventListener(eventName, () => {
            dropZone.classList.add('dragover');
        }, false);
    });

    ['dragleave', 'drop'].forEach(eventName => {
        dropZone.addEventListener(eventName, () => {
            dropZone.classList.remove('dragover');
        }, false);
    });

    dropZone.addEventListener('drop', (e) => {
        const dt = e.dataTransfer;
        const files = dt.files;
        if (files.length > 0) {
            handleFile(files[0]);
        }
    });

    dropZone.addEventListener('click', () => {
        fileInput.click();
    });

    fileInput.addEventListener('change', (e) => {
        if (e.target.files.length > 0) {
            handleFile(e.target.files[0]);
        }
    });

    function handleFile(file) {
        // Reset UI
        resultContainer.classList.add('hidden');
        
        if (!file.type.startsWith('video/')) {
            alert('Bitte lade eine gültige Videodatei hoch.');
            return;
        }

        uploadFile(file);
    }

    function uploadFile(file) {
        const formData = new FormData();
        formData.append('video', file);
        formData.append('experimental', experimentalToggle.checked);

        progressContainer.classList.remove('hidden');
        progressBar.style.width = '0%';
        progressText.textContent = 'Upload läuft...';

        const xhr = new XMLHttpRequest();
        xhr.open('POST', '/upload', true);

        xhr.upload.onprogress = (e) => {
            if (e.lengthComputable) {
                const percentComplete = (e.loaded / e.total) * 100;
                progressBar.style.width = percentComplete + '%';
                if (percentComplete === 100) {
                    progressText.textContent = 'Verarbeite Video... (Dies kann einen Moment dauern)';
                    // Simulate a slow processing progress bar
                    simulateProcessingProgress();
                }
            }
        };

        xhr.onload = () => {
            if (xhr.status === 200) {
                const response = JSON.parse(xhr.responseText);
                if (response.success) {
                    progressContainer.classList.add('hidden');
                    resultContainer.classList.remove('hidden');
                }
            } else {
                let errorMsg = 'Ein Fehler ist aufgetreten.';
                try {
                    const res = JSON.parse(xhr.responseText);
                    if (res.error) errorMsg = res.error;
                } catch(e) {}
                alert('Fehler beim Upload: ' + errorMsg);
                progressContainer.classList.add('hidden');
            }
        };

        xhr.onerror = () => {
            alert('Ein Netzwerkfehler ist aufgetreten.');
            progressContainer.classList.add('hidden');
        };

        xhr.send(formData);
    }

    function simulateProcessingProgress() {
        progressBar.style.width = '0%';
        let progress = 0;
        const interval = setInterval(() => {
            progress += Math.random() * 5;
            if (progress > 90) {
                clearInterval(interval);
            } else {
                progressBar.style.width = progress + '%';
            }
        }, 500);
    }
});
