from typing import List
import sqlalchemy as sql


class Manipulator:
    def __init__(self) -> None:
        self.engine = sql.create_engine('DB PATH')
    
    def get(self, **kwargs) -> List:
        if kwargs['all'] == 'all':
            return self.engine.execute('SELECT ALL REQUEST')
        else:
            return self.engine.execute('SELECT WITH CONDITION REQUEST')
    
    def add(self, info):
        self.engine.execute('INSERT INTO REQUEST')

    def delete(self, **criteria):
        self.engine.execute('DELETE FROM REQUEST WITH CRITERIA')
