from fastapi import FastAPI
from data_models.models import BasePainting
from db_access.manipulator import Manipulator


# TODO: Связать подгрузку файла модели и ядро
# TODO: Создать форму для ввода тестовых данных
# TODO: Создать Flask-приложения поверх API
# TODO: Распределить 5 фрагментов (25 строк), унифицировать, сохранить
# TODO: Вопрос с отрицательными значениями модели
# TODO: Тест на реальных данных модели
# TODO: Объединение мультирегрессий в единое значения со временем (временные ряды)


api = FastAPI()
db = Manipulator()


@api.get('/')
async def get_root():
    return {'ok': 200}


@api.post('/analyse')
async def analyse(painting: BasePainting):
    return {'formatted info': f'{painting.author}, {painting.painting_name}'}
