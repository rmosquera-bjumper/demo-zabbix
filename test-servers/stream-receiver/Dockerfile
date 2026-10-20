FROM python:3.13-slim

WORKDIR /app
COPY receiver.py .

EXPOSE 8090

CMD ["python", "-u", "receiver.py"]
