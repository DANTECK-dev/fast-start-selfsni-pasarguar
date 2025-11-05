#!/bin/bash
# Скрипт для инициализации Git репозитория в pasarguard-node-conf для GitHub
# Использование: cd pasarguard-node-conf && bash init-github.sh

set -e

echo "🔧 Инициализация Git репозитория для GitHub..."

# Проверка, что мы в правильной директории
if [ ! -f "selfsni-xray-pasarguard.sh" ]; then
    echo "❌ Ошибка: запустите скрипт из директории pasarguard-node-conf"
    exit 1
fi

# Проверка Git
if ! command -v git &>/dev/null; then
    echo "❌ Git не установлен. Установите: apt install git"
    exit 1
fi

# Инициализация репозитория
if [ -d ".git" ]; then
    echo "⚠️  Git репозиторий уже инициализирован"
    read -p "Переинициализировать? (y/n): " REINIT
    if [[ "$REINIT" =~ ^[Yy]$ ]]; then
        rm -rf .git
        git init
        echo "✅ Репозиторий переинициализирован"
    else
        echo "✅ Используем существующий репозиторий"
    fi
else
    git init
    echo "✅ Git репозиторий инициализирован"
fi

# Запрос URL GitHub репозитория
echo ""
echo "Введите URL вашего GitHub репозитория:"
echo "Пример: https://github.com/USERNAME/REPO-NAME.git"
read -p "GitHub URL: " GITHUB_URL

if [[ -z "$GITHUB_URL" ]]; then
    echo "❌ URL не может быть пустым"
    exit 1
fi

# Добавление remote
if git remote | grep -q "origin"; then
    git remote set-url origin "$GITHUB_URL"
    echo "✅ Remote origin обновлен"
else
    git remote add origin "$GITHUB_URL"
    echo "✅ Remote origin добавлен"
fi

# Добавление всех файлов
git add .
echo "✅ Файлы добавлены в staging"

# Создание первого коммита
if ! git log --oneline -1 &>/dev/null; then
    git commit -m "Initial commit: Self SNI + Pasarguard Node setup"
    echo "✅ Первый коммит создан"
fi

echo ""
echo "✅ Готово!"
echo ""
echo "Следующие шаги:"
echo "1. Создайте репозиторий на GitHub (если еще не создан)"
echo "2. Запушьте код:"
echo "   git push -u origin main"
echo "   или"
echo "   git push -u origin master"
echo ""
echo "3. После этого обновите URL в selfsni-xray-pasarguard.sh и README.md"
echo "   Замените USER/REPO на ваш GitHub репозиторий"
