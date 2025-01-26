import boto3
import requests
import os
from botocore.exceptions import ClientError

# Inicializa el cliente de DynamoDB
dynamodb = boto3.client('dynamodb')

# Variables de entorno
TABLE_NAME = os.environ['DYNAMODB_TABLE']
WEBHOOK_URL = os.environ['WEBHOOK_URL']

def fetch_pending_transactions():
    """Consulta DynamoDB para obtener todas las transacciones pendientes."""
    try:
        response = dynamodb.scan(
            TableName=TABLE_NAME,
            FilterExpression="status = :status",
            ExpressionAttributeValues={":status": {"S": "pending"}}
        )
        items = response.get('Items', [])
        
        # Manejo de paginación
        while 'LastEvaluatedKey' in response:
            response = dynamodb.scan(
                TableName=TABLE_NAME,
                FilterExpression="status = :status",
                ExpressionAttributeValues={":status": {"S": "pending"}},
                ExclusiveStartKey=response['LastEvaluatedKey']
            )
            items.extend(response.get('Items', []))
        
        return items
    except ClientError as e:
        print(f"Error al consultar DynamoDB: {e}")
        return []

def send_to_webhook(transactions):
    """Envía las transacciones al webhook del cliente."""
    try:
        payload = {"transactions": transactions}
        response = requests.post(WEBHOOK_URL, json=payload)
        response.raise_for_status()
        return response.status_code
    except requests.exceptions.RequestException as e:
        print(f"Error al enviar al webhook: {e}")
        return None

def mark_transactions_completed(transactions):
    """Actualiza el estado de las transacciones a 'completed' en DynamoDB."""
    try:
        for transaction in transactions:
            dynamodb.update_item(
                TableName=TABLE_NAME,
                Key={"transaction_id": transaction["transaction_id"]},
                UpdateExpression="SET #status = :completed",
                ExpressionAttributeNames={"#status": "status"},
                ExpressionAttributeValues={":completed": {"S": "completed"}}
            )
    except ClientError as e:
        print(f"Error al actualizar DynamoDB: {e}")

def lambda_handler(event, context):
    # Paso 1: Consultar transacciones pendientes
    pending_transactions = fetch_pending_transactions()
    
    if not pending_transactions:
        return {"statusCode": 200, "body": "No hay transacciones pendientes"}
    
    # Convertir datos de DynamoDB a un formato JSON simple
    formatted_transactions = [
        {key: list(value.values())[0] for key, value in item.items()}
        for item in pending_transactions
    ]
    
    # Paso 2: Enviar transacciones al webhook
    webhook_status = send_to_webhook(formatted_transactions)
    
    if webhook_status == 200:
        # Paso 3: Marcar transacciones como completadas
        mark_transactions_completed(pending_transactions)
        return {"statusCode": 200, "body": "Transacciones procesadas con éxito"}
    else:
        return {"statusCode": 500, "body": "Error al enviar las transacciones al webhook"}
