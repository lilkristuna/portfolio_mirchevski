FROM python:3.9-slim

WORKDIR /app

COPY ./policy-manager-service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY ./policy-manager-service/policy_manager_service.py .

RUN mkdir -p /app/policies
COPY ./policies/default_policies.yaml /app/policies/

EXPOSE 8000 8001

CMD ["python", "policy_manager_service.py"]