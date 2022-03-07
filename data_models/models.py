from pydantic import BaseModel

class BasePainting(BaseModel):
    author: str
    painting_name: str