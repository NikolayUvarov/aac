#import sys
#import json
#from lxml import etree
#import os
#import time
#import re
import sqlite3


#--------------------------------------------------------------------------------------------------------------

_logName = "agentsKeeper"
import logging
logger = logging.getLogger(_logName)

#--------------------------------------------------------------------------------------------------------------

class agentsDataKeeper:

    #-------------
    def __init__(self, data_folder_name):
        self._db_file_name = data_folder_name + "/agents.db"
        self._connection = None

    #-------------
    def __del__(self):
        if not self._connection is None:
            self._connection.commit()
            self._connection.close()

    #-------------
    def init_data(self):

        if self._connection is None:
            try:
                self._connection = sqlite3.connect(self._db_file_name)
            except sqlite3.Error as e:
                logger.error(f"Error connecting to database {repr(self._db_file_name)}: {e}")
                raise

        self._create_tables_if_needed()

    #-------------

    def _table_exists(self, table_name, cursor):
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table_name,) )
        return not cursor.fetchone() is None 

    #-------------

    def _create_tables_if_needed(self):
        cursor = self._connection.cursor()

        for tname in ('Agents','Tags'):
            logger.info(f"Table {repr(tname)} in database {repr(self._db_file_name)} {'exists' if self._table_exists(tname, cursor) else 'to be created'}")

        cursor.execute( '''
            CREATE TABLE IF NOT EXISTS Agents (
                agent_id TEXT PRIMARY KEY,
                branch TEXT,
                descr TEXT,
                location TEXT,
                extra TEXT
            )
        ''')

        cursor.execute( '''
            CREATE TABLE IF NOT EXISTS Tags (
                tag_id INTEGER PRIMARY KEY AUTOINCREMENT,
                agent_id TEXT,
                tag TEXT,
                FOREIGN KEY (agent_id) REFERENCES Agents (agent_id)
            )
        ''')

        self._connection.commit()
        cursor.close()

    #-------------

    def get_all_agent_ids(self):
        cursor = self._connection.cursor()
        cursor.execute("SELECT agent_id FROM Agents")
        ret = [ row[0] for row in iter(cursor.fetchone,None) ]
        cursor.close()
        return ret

    #-------------

    def get_branch_name(self, agent_id):
        cursor = self._connection.cursor()
        cursor.execute("SELECT branch FROM Agents WHERE agent_id=?", (agent_id,))
        row = cursor.fetchone()
        cursor.close()
        return None if row is None else row[0]

    #-------------

    def get_agent_dict(self, agent_id, with_tags=False):
        cursor = self._connection.cursor()

        cursor.execute("SELECT * FROM Agents WHERE agent_id=?", (agent_id,))
        row = cursor.fetchone()
        ret = None if row is None else dict(zip( ("agent_id","branch","descr","location","extra"), row ))

        if with_tags and not ret is None:
            cursor.execute("SELECT tag FROM Tags WHERE agent_id=?", (agent_id,))
            ret['tags'] = [row[0] for row in cursor.fetchall()]

        cursor.close()
        return ret
        
    #-------------
    '''
    def change_agent_branch(self, agent_id, new_branch_name):
        cursor = self._connection.cursor()
        cursor.execute("UPDATE Agents SET branch=? WHERE agent_id=?", (new_branch_name, agent_id,))
        ret = cursor.rowcount > 0
        self._connection.commit()
        cursor.close()
        return ret
    '''
    #-------------

    def add_agent(self, agent_id, branch, descr="", location="", extra="", tags=()):
        cursor = self._connection.cursor()
        cursor.execute( "INSERT INTO Agents (agent_id, branch, descr, location, extra) VALUES (?, ?, ?, ?, ?)", (agent_id, branch, descr, location, extra,) )
        for tag in tags:
            cursor.execute("INSERT INTO Tags (agent_id, tag) VALUES (?, ?)", (agent_id, tag,))
        self._connection.commit()
        cursor.close()

    #-------------

    def delete_agent(self, agent_id):
        cursor = self._connection.cursor()

        cursor.execute("DELETE FROM Tags WHERE agent_id=?", (agent_id,))

        cursor.execute("DELETE FROM Agents WHERE agent_id=?", (agent_id,))
        deleted_rows = cursor.rowcount

        self._connection.commit()
        cursor.close()

        return deleted_rows>0

    #-------------

    def get_agents_by_branch_list(self, branch_names):
        cursor = self._connection.cursor()

        query = "SELECT agent_id,branch FROM Agents WHERE branch IN ({})".format(",".join(["?"] * len(branch_names)))
        cursor.execute(query, branch_names)
        agents = cursor.fetchall()

        cursor.close()
        return agents


#--------------------------------------------------------------------------------------------------------------
# Some self-test functionality

if __name__ == '__main__':

    import configTestLogging
    configTestLogging.config(_logName)

    #~~~~~~~~~~~~~~~~~~~~~~~

    def main():        
        test = agentsDataKeeper("DATA")
        test.init_data()

    main()

