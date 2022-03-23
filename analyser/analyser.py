import datetime 
import pickle
from sklearn import linear_model
import re
from utils.helpers import load_settings
from utils.helpers import load_df
from utils.helpers import format_answer


class Analyser:
    def __init__(self) -> None:
        self.settings = load_settings('analyser')
        self.model = None

    @staticmethod
    def RaitAdap(rait):
        if type(rait)==str:
            if rait[0].isdigit():
                return int(rait[0])
            else:
                return int(rait[1])
        return rait
        
    @staticmethod
    def dim(point):
        return int(point[0])

    @staticmethod
    def DateCreateAdap(Date):
        if type(Date)==str:
            s = [float(s) for s in re.findall(r'-?\d+\.?\d*', Date)]
            return s[0]
        else:
            return Date
        
    @staticmethod
    def DateToDay(Date):
        return Date.toordinal()
        
    @staticmethod
    def ShifrAdap(shifr):
        if type(shifr) == str:
            return int(shifr[1:])

    @staticmethod
    def DateAdap(Date):
        if type(Date) == str:
            Date = datetime.datetime.strptime(Date, '%Y-%m-%d')
            Date = datetime.date(Date.year, Date.month, Date.day)
            return Date

    @staticmethod
    def DataTrainAdap(df):
        df[""]
        pass

    @staticmethod
    def NxM_to_sqr(Str):    # 30x40 cm -> в площадь
        s = [float(s) for s in re.findall(r'-?\d+\.?\d*', Str)]
        Sum = 1
        for i in s:
            Sum*=i
        return Sum
        
    @staticmethod
    def Predictor(model,filtr):
        X =[[]]
        for i in filtr:
            X[0].append(input(f"{i}: "))
        Y = model.predict(X)
        print(Y)
    
    def load_model(self, modelname):
        self.model = pickle.load(open(modelname, 'rb'))

    def save_model(self, model):
        pickle.dump(model, open(f'regressions/model_{datetime.datetime.now().day}_{datetime.datetime.now().month}.pickle', 'wb'))

    def create_model(self):
        df = load_df()
        word1 = "Цена_продажи"
        word2 = "Дата_продажи"

        code = '123456'

        zipper = ["№_В.И.", "Измерение", "Рейтинг_автора", "Размер_произведения","Год_создания", "№_О.", "Шифр_картины"]  #!!!!!!!!!!
        used_features = [word1, word2]
        for i in code:
            used_features.append(zipper[int(i)-1])
        
        df = df[used_features]
        df = df.dropna()
        df_copy = df.copy(deep=True) 
        
        try:
            df_copy["Дата_продажи"] = df["Дата_продажи"].apply(self.DateAdap)
            df["Дата_продажи"] = df_copy["Дата_продажи"]
            df["Дата_продажи"] = df["Дата_продажи"].apply(self.DateToDay)
        except KeyError:
            pass
        try:
            df["Размер_произведения"] = df["Размер_произведения"].apply(self.NxM_to_sqr)
        except KeyError:
            pass
        try:
            df["Год_создания"] = df["Год_создания"].apply(self.DateCreateAdap)
        except KeyError:
            pass
        try:
            df["Рейтинг_автора"] = df["Рейтинг_автора"].apply(self.RaitAdap)
        except KeyError:
            pass
        try:
            df["Измерение"] = df["Измерение"].apply(self.dim)
        except:
            pass
        try:
            df["Шифр_картины"] = df["Шифр_картины"].apply(self.ShifrAdap)
        except:
            pass

        Y = df[word1]
        used_features.remove(word1)
        X = df[used_features]
        
        self.model = linear_model.LinearRegression().fit(X.values, Y.values)
        middle_half = (df['Цена_продажи'].mean() / 2)
        self.model.middle = middle_half
        
        self.save_model(self.model)

    def analyse(self, data):
        if self.model is None:
            self.create_model()
                        
        pred = format_answer(self.model.predict([data])[0], self.model.middle)

        return pred

        