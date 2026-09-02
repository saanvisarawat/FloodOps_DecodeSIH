import requests

def test_flood_model_endpoint():
    url = "http://127.0.0.1:8000/api/ml/predict-kerala"  
    payload = {
        "lat": 9.9189,
        "lon": 77.1025,
        "district": "Idukki"
    }
    
    try:
        print("🚀 Sending test request to FastAPI backend...")
        response = requests.post(url, json=payload) # Change to requests.get if your endpoint uses query parameters
        
        if response.status_code == 200:
            print("✅ Success! The backend successfully integrated and ran the model.")
            print("📦 Response from backend:", response.json())
        else:
            print(f"❌ Backend error (Status {response.status_code}):")
            print(response.text)
            
    except requests.exceptions.ConnectionError:
        print("❌ Connection refused. Make sure your FastAPI server is running with 'uvicorn app.main:app --reload'")
    except Exception as e:
        print(f"❌ An error occurred: {e}")

if __name__ == "__main__":
    test_flood_model_endpoint()