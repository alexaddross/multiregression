class UnspecifiedModuleException(BaseException):
    def __init__(self):
        super().__init__('Cannot connect to the database')