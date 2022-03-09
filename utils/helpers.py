import json
from utils.errors import UnspecifiedModuleException


def load_settings(module=None):
    if module is None:
        raise UnspecifiedModuleException
    else:
        settings = json.load(open(module + '/settings.json'))
    
    return settings