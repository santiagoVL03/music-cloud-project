# Test script to verify the backend functionality

import requests
import json

# Base URL for the API
BASE_URL = "http://localhost:8000"

def test_api():
    """Test all API endpoints"""
    print("🎵 Testing Music Cloud API 🎵\n")
    
    try:
        # Test 1: Get all music
        print("1. Testing GET /musica")
        response = requests.get(f"{BASE_URL}/musica")
        if response.status_code == 200:
            print(f"Success! Found {len(response.json())} songs")
            print(f"First song: {response.json()[0] if response.json() else 'No songs found'}")
        else:
            print(f"Error: {response.status_code}")
        print()
        
        # Test 2: Create a new user
        print("2. Testing POST /usuarios")
        new_user = {
            "nombre": "Test User",
            "email": "test@example.com"
        }
        response = requests.post(f"{BASE_URL}/usuarios", json=new_user)
        if response.status_code == 201:
            user_data = response.json()
            user_id = user_data["id"]
            print(f"Success! Created user with ID: {user_id}")
            print(f"User data: {user_data}")
        else:
            print(f"Error: {response.status_code} - {response.text}")
            return
        print()
        
        # Test 3: Get user profile
        print(f"3. Testing GET /usuarios/{user_id}")
        response = requests.get(f"{BASE_URL}/usuarios/{user_id}")
        if response.status_code == 200:
            profile = response.json()
            print(f"Success! User profile retrieved")
            print(f"Profile: {profile}")
        else:
            print(f"Error: {response.status_code}")
        print()
        
        # Test 4: Add music to user's library
        print(f"4. Testing POST /usuarios/{user_id}/musica")
        add_music = {"musica_id": 1}  # Assuming music with ID 1 exists
        response = requests.post(f"{BASE_URL}/usuarios/{user_id}/musica", json=add_music)
        if response.status_code == 200:
            print(f"Success! Added music to user's library")
            print(f"Response: {response.json()}")
        else:
            print(f"Error: {response.status_code} - {response.text}")
        print()
        
        # Test 5: Update user status
        print(f"5. Testing PUT /usuarios/{user_id}/estado")
        update_status = {"estado": False}
        response = requests.put(f"{BASE_URL}/usuarios/{user_id}/estado", json=update_status)
        if response.status_code == 200:
            updated_user = response.json()
            print(f"Success! Updated user status")
            print(f"Updated user: {updated_user}")
        else:
            print(f"Error: {response.status_code}")
        print()
        
        # Test 6: Get updated user profile
        print(f"6. Testing GET /usuarios/{user_id} (after update)")
        response = requests.get(f"{BASE_URL}/usuarios/{user_id}")
        if response.status_code == 200:
            profile = response.json()
            print(f"Success! Updated profile retrieved")
            print(f"Profile with music: {profile}")
        else:
            print(f"Error: {response.status_code}")

        print("\nAll tests completed!")
        
    except requests.exceptions.ConnectionError:
        print("Connection Error: Make sure the server is running on http://localhost:8000")
    except Exception as e:
        print(f"Unexpected error: {e}")

if __name__ == "__main__":
    test_api()
