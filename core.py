from fastapi import FastAPI
from fastapi import Form
from data_models.models import BasePainting


api = FastAPI()


@api.get('/')
async def get_root():
    return {'ok': 200}

@api.post('/analyse')
async def analyse(painting: BasePainting):
    return {'formatted info': f'{painting.author}, {painting.painting_name}'}
