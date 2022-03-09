import requests


def test_analyse_endpoint():
    result = requests.post('http://127.0.0.1:8000/analyse', json={'author': 'Aisek', 'painting_name': 'The Wall'})
    
    assert result.text == '{"formatted info":"Aisek, The Wall"}'
