import pandas as pd
import sqlite3
import datetime
from sklearn import linear_model
from sklearn.model_selection import train_test_split as tts
import seaborn as sea
import matplotlib 
import re
import numpy as np


def RaitAdap(rait):
    if type(rait)==str:
        if rait[0].isdigit():
            return int(rait[0])
        else:
            return int(rait[1])
    return rait
    

def dim(point):
    return int(point[0])


def DateCreateAdap(Date):
    if type(Date)==str:
        s = [float(s) for s in re.findall(r'-?\d+\.?\d*', Date)]
        return s[0]
    else:
        return Date
    

def DateToDay(date):
    return date.toordinal()


def ShifrAdap(shifer):
    if type(shifer) == str:
        return int(shifer[1:])


def DateAdap(date):
    if type(date) == str:
        date = datetime.datetime.strptime(date, '%Y-%m-%d')
        date = datetime.date(date.year, date.month, date.day)

        return date


def NxM_to_sqr(size_in_str):
    a, b = [float(part) for part in size_in_str.split('x')]
    
    return a * b


def TrainDF(linear, X, Y):
    #Тренируем нейронку
    model = linear.LinearRegression(X, Y)

    return model


def Predictor(model, filter):
    x = [[]]

    for i in filter:
        x[0].append(input(f"{i}: "))

    y = model.predict(x)
    return y
    

def StartUP():
    conn = sqlite3.connect("Main_base.db", detect_types=sqlite3.PARSE_DECLTYPES | sqlite3.PARSE_COLNAMES)
    df = pd.read_sql_query("SELECT * FROM Offer", conn)
    word1 = "Цена_продажи"
    word2 = "Дата_продажи"
    
    # Оставляем в ДатаФрейме лишь те поля, что будут отмечены пользователям для того, чтобы по ним тренировать линейную регрессию.
    code = input("Перечислите все фильтры строкой без запятых и др знаков не нарушая порядка перечисления.")
    zipper = ["№_В.И.", "Измерение", "Рейтинг_автора", "Размер_произведения", "Год_создания", "№_О.", "Шифр_картины"]
    filter = [word1, word2]

    for i in code:
        filter.append(zipper[int(i) - 1])
        
    print("Фильтр :\n ", filter)
    df = df[filter]
    df = df.dropna()
    df_copy = df.copy(deep=True)    

    try:
        df_copy["Дата_продажи"] = df["Дата_продажи"].apply(DateAdap)
        df["Дата_продажи"] = df_copy["Дата_продажи"]
        df["Дата_продажи"] = df["Дата_продажи"].apply(DateToDay)
    except KeyError:
        pass
    
    try:
        df["Размер_произведения"] = df["Размер_произведения"].apply(NxM_to_sqr)
    except KeyError:
        pass
    
    try:
        df["Год_создания"] = df["Год_создания"].apply(DateCreateAdap)
    except KeyError:
        pass
    
    try:
        df["Рейтинг_автора"] = df["Рейтинг_автора"].apply(RaitAdap)
    except KeyError:
        pass
    
    try:
        df["Измерение"] = df["Измерение"].apply(dim)
    except:
        pass
    
    try:
        df["Шифр_картины"] = df["Шифр_картины"].apply(ShifrAdap)
    except:
        pass
        

    y = df[word1]
    filter.remove(word1)
    x = df[filter]
    model = linear_model.LinearRegression().fit(x, y)
    pred = model.predict(x)

    real = x.copy(deep=True)
    predicted = x.copy(deep=True)
    real["Цена_продажи"] = y
    predicted["Цена_предсказания"] = pred

    for i in x.keys():
            sea.scatterplot(data=real, x=i, y="Цена_продажи")
            sea.lineplot(data=real, x=i, y="Цена_продажи")

            sea.lineplot(data = predicted, x=i, y="Цена_предсказания")
    
    result = [filter, real, predicted, model, df]

    return result