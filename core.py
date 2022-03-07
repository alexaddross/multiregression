from fastapi import FastAPI

api = FastAPI()


@api.get('/')
def get_root():
    return {'ok': 200}

