#!/bin/bash
set -e

echo "📦 Esperando a que la base de datos esté lista..."
until pg_isready -h db -U santiago -d musiccloud; do
  sleep 2
done

echo "🚀 Ejecutando init_data.py..."
python init_data.py

echo "🌐 Iniciando aplicación FastAPI..."
exec uvicorn main:app --host 0.0.0.0 --port 8000 --reload
