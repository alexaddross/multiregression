import pandas as pd
import sqlite3
import time
import datetime 
import heapq
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
    

def DateToDay(Date):
    return Date.toordinal()
    
def ShifrAdap(shifr):
    if type(shifr) == str:
        return int(shifr[1:])
def DateAdap(Date):
    if type(Date) == str:
        Date = datetime.datetime.strptime(Date, '%Y-%m-%d')
        Date = datetime.date(Date.year, Date.month, Date.day)
        return Date

def DataTrainAdap(df):
    df[""]
    pass
    
    


def NxM_to_sqr(Str):    # 30x40 cm -> в площадь
    
    s = [float(s) for s in re.findall(r'-?\d+\.?\d*', Str)]
    Sum = 1
    for i in s:
        Sum*=i
    return Sum

          

def AdaptatorData4T(df): # Адаптатор для тренировки LinearRegression
     df["Дата_продажи"] = df["Дата_продажи"].apply(date_to_day)
     df["Дата_изготовления"] = df["Дата_изготовления"].apply(date_to_day)
     df["Размер"] = df["Размер"].apply(NxM_to_sqr) #???
     df["Шифр"] = df["Шифр"].apply(shifr_to_int)  # !!!!!
     adap_df = df.apply(int)
     return adap_df
     



def TrainDF(X,Y):
    #Тренируем нейронку
    model = linear.LinearRegression(X,Y)
    #Отправим модель для того, чтобы потом предиктить по ней что-нибудь
    return model

def Predictor(model, filter):
    x = [[]]

    for i in filter:
        x[0].append(input(f"{i}: "))

    y = model.predict(x)
    return y
    

def StartUP():
    conn = sqlite3.connect("Main_base.db", detect_types=sqlite3.PARSE_DECLTYPES |
                                    sqlite3.PARSE_COLNAMES)
    df = pd.read_sql_query("SELECT * FROM Offer", conn)
    word1 = "Цена_продажи"
    word2 = "Дата_продажи"
    
    
    
    # Оставляем в ДатаФрейме лишь те поля, что будут отмечены пользователям для того, чтобы по ним тренировать линейную регрессию.
    code = input("Перечислите все фильтры строкой без запятых и др знаков не нарушая порядка перечисления.")
    zipper = ["№_В.И.", "Измерение", "Рейтинг_автора", "Размер_произведения","Год_создания", "№_О.","Шифр_картины"]  #!!!!!!!!!!
    filtr = [word1, word2]

    for i in code:
        filtr.append(zipper[int(i) - 1])
        
    print("Фильтр :\n ", filtr)
    df = df[filtr]
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
    filtr.remove(word1)
    x = df[filtr]


    model = linear_model.LinearRegression().fit(x, y)
    pred = model.predict(x)
    real = x.copy(deep=True)
    predicted = x.copy(deep=True)
    real["Цена_продажи"] = y
    predicted["Цена_предсказания"] = pred
    for i in x.keys():
            #sea.scatterplot(data = predicted ,x=i,y="Цена_предсказания")
            #sea.lineplot(x=X[i].values,y=pred)
            
            sea.scatterplot(data=real, x=i, y="Цена_продажи")
            sea.lineplot(data=real, x=i, y="Цена_продажи")

            sea.lineplot(data = predicted, x=i, y="Цена_предсказания")
    
    matplotlib.pyplot.show()

    print(df["Дата_продажи"].values)
    
    result=[filtr,real,predicted,model,df]
    return result