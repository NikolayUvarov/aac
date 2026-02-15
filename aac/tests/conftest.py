"""Shared fixtures for AAC smoke tests."""
import os
import shutil
import tempfile
import pytest
import sys

# Make the aac package importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


@pytest.fixture()
def storage(tmp_path):
    """Create a configDataKeeper backed by a temporary copy of DATA.vanila."""
    src = os.path.join(os.path.dirname(__file__), "..", "DATA.vanila")
    data_dir = str(tmp_path / "DATA")
    shutil.copytree(src, data_dir)

    # Create a minimal agents.db so agentsKeeper can initialise
    import sqlite3
    db_path = os.path.join(data_dir, "agents.db")
    conn = sqlite3.connect(db_path)
    conn.execute("""CREATE TABLE IF NOT EXISTS Agents (
        agent_id TEXT PRIMARY KEY, branch TEXT, descr TEXT, location TEXT, extra TEXT)""")
    conn.execute("""CREATE TABLE IF NOT EXISTS Tags (
        tag_id INTEGER PRIMARY KEY AUTOINCREMENT,
        agent_id TEXT, tag TEXT,
        FOREIGN KEY (agent_id) REFERENCES Agents(agent_id))""")
    conn.commit()
    conn.close()

    from dataKeeper import configDataKeeper
    dk = configDataKeeper(data_dir, 60)
    dk.load()
    return dk
