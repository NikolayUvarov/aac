import logging
import logging.config

def config(logName):

    logging.config.dictConfig({
        'version': 1,
        'formatters': {
            'forview': { 'format': '[%(asctime)s] %(levelname)s in %(name)s: %(message)s', },
            'fordisk': { 'format': '%(asctime)s %(levelname)-8s %(name)-15s %(message)s', }
        },
        'handlers': {
            'cons': { 'class': 'logging.StreamHandler',                'formatter': 'forview', 'level': 'DEBUG'},
            'disk': { 'class' :'logging.handlers.RotatingFileHandler', 'formatter': 'fordisk', 'level': 'DEBUG',
                      'filename': logName+'.log', 'maxBytes': 100_000_000,'backupCount': 9,
                      'encoding': 'UTF-8', 
                    },
        },
        'loggers': {
            "root":   { 'level': 'INFO', 'handlers': ['cons','disk'] },
            logName: { 'level': 'DEBUG', 'handlers': ['cons','disk'], 'propagate':0 }
        }
    })

