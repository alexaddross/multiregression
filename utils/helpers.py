import json
import sqlite3
import pandas as pd
from utils.errors import UnspecifiedModuleException


def load_settings(module=None):
    if module is None:
        raise UnspecifiedModuleException
    else:
        settings = json.load(open(module + '/settings.json'))
    
    return settings

def load_df(table='Offer'):
    conn = sqlite3.connect("database.db", detect_types=sqlite3.PARSE_DECLTYPES |
                                    sqlite3.PARSE_COLNAMES)
    return pd.read_sql_query(f"SELECT * FROM {table}", conn)

def format_answer(x, mid):
    return mid if x < mid else x