document.addEventListener('DOMContentLoaded', function() {
    // Обработка переключения HTTPS
    const httpsForm = document.getElementById('https-form');
    if (httpsForm) {
        httpsForm.addEventListener('submit', function(e) {
            e.preventDefault();
            const useHttps = document.getElementById('use-https').checked;
            
            fetch('/toggle_https', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                    'X-CSRFToken': document.querySelector('meta[name="csrf-token"]').content
                },
                body: `use_https=${useHttps}`
            })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    alert(data.message);
                } else {
                    alert('Ошибка: ' + data.message);
                }
            })
            .catch(error => {
                console.error('Error:', error);
                alert('Произошла ошибка при обновлении настроек HTTPS');
            });
        });
    }

    // Генерация тестовых сертификатов
    const generateTestCertsBtn = document.getElementById('generate-test-certs');
    if (generateTestCertsBtn) {
        generateTestCertsBtn.addEventListener('click', function() {
            if (confirm('Создать тестовые сертификаты? Они будут действительны только для localhost.')) {
                fetch('/generate_test_certs', {
                    method: 'POST',
                    headers: {
                        'X-CSRFToken': document.querySelector('meta[name="csrf-token"]').content
                    }
                })
                .then(response => response.json())
                .then(data => {
                    alert(data.message);
                })
                .catch(error => {
                    console.error('Error:', error);
                    alert('Произошла ошибка при создании сертификатов');
                });
            }
        });
    }

    // Загрузка сертификатов
    const uploadCertsForm = document.getElementById('upload-certs-form');
    if (uploadCertsForm) {
        uploadCertsForm.addEventListener('submit', function(e) {
            e.preventDefault();
            
            const formData = new FormData(uploadCertsForm);
            
            fetch('/upload_certs', {
                method: 'POST',
                headers: {
                    'X-CSRFToken': document.querySelector('meta[name="csrf-token"]').content
                },
                body: formData
            })
            .then(response => response.json())
            .then(data => {
                alert(data.message);
            })
            .catch(error => {
                console.error('Error:', error);
                alert('Произошла ошибка при загрузке сертификатов');
            });
        });
    }
});