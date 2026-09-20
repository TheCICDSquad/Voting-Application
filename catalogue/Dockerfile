FROM python:3.11-slim
WORKDIR /app

RUN groupadd -r craftista && useradd -r -g craftista craftista

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN rm -f app.py.bak

ENV PYTHONUNBUFFERED=1
EXPOSE 5000
USER craftista

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
