import os
import psycopg2
from dotenv import load_dotenv

# Načte proměnné ze souboru .env
load_dotenv()

# Získá URL adresu databáze
db_url = os.getenv("DATABASE_URL")

def test_neon_connection():
    if not db_url:
        print("❌ Chyba: DATABASE_URL nebyla nalezena. Zkontroluj .env soubor.")
        return

    try:
        # Pokus o připojení
        conn = psycopg2.connect(db_url)
        cur = conn.cursor()
        
        # Dotaz, který zjistí seznam tvých tabulek
        cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';")
        tables = cur.fetchall()
        
        print("✅ Připojení k databázi Neon.tech bylo ÚSPĚŠNÉ!")
        print(f"📦 Nalezené tabulky v public schématu:")
        for table in tables:
            print(f" - {table[0]}")
            
        cur.close()
        conn.close()
        
    except Exception as e:
        print(f"❌ Nastala chyba při připojování k Neonu:\n{e}")

if __name__ == "__main__":
    test_neon_connection()