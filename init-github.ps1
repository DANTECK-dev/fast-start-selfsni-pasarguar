# Скрипт для инициализации Git репозитория в pasarguard-node-conf для GitHub (PowerShell)
# Использование: cd pasarguard-node-conf; .\init-github.ps1

Write-Host "🔧 Инициализация Git репозитория для GitHub..." -ForegroundColor Cyan

# Проверка, что мы в правильной директории
if (-not (Test-Path "selfsni-xray-pasarguard.sh")) {
    Write-Host "❌ Ошибка: запустите скрипт из директории pasarguard-node-conf" -ForegroundColor Red
    exit 1
}

# Проверка Git
try {
    $null = git --version
} catch {
    Write-Host "❌ Git не установлен. Установите Git for Windows" -ForegroundColor Red
    exit 1
}

# Инициализация репозитория
if (Test-Path ".git") {
    Write-Host "⚠️  Git репозиторий уже инициализирован" -ForegroundColor Yellow
    $reinit = Read-Host "Переинициализировать? (y/n)"
    if ($reinit -eq "y" -or $reinit -eq "Y") {
        Remove-Item -Recurse -Force .git
        git init
        Write-Host "✅ Репозиторий переинициализирован" -ForegroundColor Green
    } else {
        Write-Host "✅ Используем существующий репозиторий" -ForegroundColor Green
    }
} else {
    git init
    Write-Host "✅ Git репозиторий инициализирован" -ForegroundColor Green
}

# Запрос URL GitHub репозитория
Write-Host ""
Write-Host "Введите URL вашего GitHub репозитория:"
Write-Host "Пример: https://github.com/USERNAME/REPO-NAME.git"
$githubUrl = Read-Host "GitHub URL"

if ([string]::IsNullOrWhiteSpace($githubUrl)) {
    Write-Host "❌ URL не может быть пустым" -ForegroundColor Red
    exit 1
}

# Добавление remote
$remotes = git remote
if ($remotes -contains "origin") {
    git remote set-url origin $githubUrl
    Write-Host "✅ Remote origin обновлен" -ForegroundColor Green
} else {
    git remote add origin $githubUrl
    Write-Host "✅ Remote origin добавлен" -ForegroundColor Green
}

# Добавление всех файлов
git add .
Write-Host "✅ Файлы добавлены в staging" -ForegroundColor Green

# Создание первого коммита
$lastCommit = git log --oneline -1 2>$null
if (-not $lastCommit) {
    git commit -m "Initial commit: Self SNI + Pasarguard Node setup"
    Write-Host "✅ Первый коммит создан" -ForegroundColor Green
}

Write-Host ""
Write-Host "✅ Готово!" -ForegroundColor Green
Write-Host ""
Write-Host "Следующие шаги:"
Write-Host "1. Создайте репозиторий на GitHub (если еще не создан)"
Write-Host "2. Запушьте код:"
Write-Host "   git push -u origin main"
Write-Host "   или"
Write-Host "   git push -u origin master"
Write-Host ""
Write-Host "3. После этого обновите URL в selfsni-xray-pasarguard.sh и README.md"
Write-Host "   Замените USER/REPO на ваш GitHub репозиторий"

