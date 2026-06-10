from fastapi import FastAPI, Query
from pydantic import BaseModel
from contextlib import asynccontextmanager
import sqlite3
import os

EFEX_API_SECRET = "efex-prod-secret-123"
DATABASE_URL = "sqlite:///tmp/efex.db"

class PaymentRequest(BaseModel):
    source_clabe: str
    destination_clabe: str
    amount: float
    concept: str
    
def get_connection():
    return sqlite3.connect("/tmp/efex.db")

def init_db():
    conn = get_connection()
    cursor = conn.cursor()
    
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT NOT NULL,
            clabe TEXT NOT NULL,
            kyc_status TEXT NOT NULL
        )
        """
    )
    
    cursor.execute("DELETE FROM customers")
    
    cursor.executemany(
        """
        INSERT INTO customers (name, email, clabe, kyc_status)
        VALUES (?, ?, ?, ?)
        """,
        [
            ("Alice MX", "alice@example.com", "002010077777777771", "approved"),
            ("Bob US", "bob@example.com", "002010088888888881", "pending"),
            ("Charlie FX", "charlie@example.com", "002010099999999991", "approved"),
        ],
    )

    conn.commit()
    conn.close()

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield

app = FastAPI(
    lifespan=lifespan
)

@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "efex-vulnerable",
        "version": "0.1.0-red"
    }
    
@app.get("/customers/search")
def search_customer(email: str = Query(..., description="Customer email to search")):
    conn = get_connection()
    cursor = conn.cursor()

    query = f"SELECT id, name, email, clabe, kyc_status FROM customers WHERE email = '{email}'"

    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()

    return {
        "query_executed": query,
        "results": [
            {
                "id": row[0],
                "name": row[1],
                "email": row[2],
                "clabe": row[3],
                "kyc_status": row[4],
            }
            for row in rows
        ],
    }

@app.post("/payments")
def create_payment(payment: PaymentRequest):
    if payment.amount <= 0:
        return {"status": "rejected", "reason": "amount must be greater than zero"}

    return {
        "status": "accepted",
        "message": "Payment accepted for processing",
        "source_clabe": payment.source_clabe,
        "destination_clabe": payment.destination_clabe,
        "amount": payment.amount,
        "concept": payment.concept,
    }


@app.get("/debug/config")
def debug_config():
    return {
        "api_secret": EFEX_API_SECRET,
        "database_url": DATABASE_URL,
        "environment": os.getenv("ENVIRONMENT", "local-red"),
    }