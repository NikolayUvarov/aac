package main

import (
    "database/sql"
    "fmt"
    "sort"
    "strings"
    _ "modernc.org/sqlite"
)

type agentsKeeper struct {
    dbFile string
    db     *sql.DB
}

func newAgentsKeeper(dataFolder string) *agentsKeeper {
    return &agentsKeeper{dbFile: dataFolder + "/agents.db"}
}

func (ak *agentsKeeper) initData() error {
    if ak.db != nil {
        return nil
    }

    db, err := sql.Open("sqlite", ak.dbFile)
    if err != nil {
        return err
    }

    ak.db = db
    return ak.createTablesIfNeeded()
}

func (ak *agentsKeeper) createTablesIfNeeded() error {
    _, err := ak.db.Exec(`
        CREATE TABLE IF NOT EXISTS Agents (
            agent_id TEXT PRIMARY KEY,
            branch TEXT,
            descr TEXT,
            location TEXT,
            extra TEXT
        )
    `)
    if err != nil {
        return err
    }

    _, err = ak.db.Exec(`
        CREATE TABLE IF NOT EXISTS Tags (
            tag_id INTEGER PRIMARY KEY AUTOINCREMENT,
            agent_id TEXT,
            tag TEXT,
            FOREIGN KEY (agent_id) REFERENCES Agents (agent_id)
        )
    `)
    return err
}

func (ak *agentsKeeper) close() {
    if ak.db != nil {
        _ = ak.db.Close()
        ak.db = nil
    }
}

func (ak *agentsKeeper) getAllAgentIds() []string {
    if ak.db == nil {
        return []string{}
    }
    rows, err := ak.db.Query(`SELECT agent_id FROM Agents`)
    if err != nil {
        return []string{}
    }
    defer rows.Close()

    out := []string{}
    for rows.Next() {
        var agentID string
        if err := rows.Scan(&agentID); err == nil {
            out = append(out, agentID)
        }
    }
    sort.Strings(out)
    return out
}

func (ak *agentsKeeper) getBranchName(agentID string) (string, bool) {
    if ak.db == nil {
        return "", false
    }
    row := ak.db.QueryRow(`SELECT branch FROM Agents WHERE agent_id = ?`, agentID)
    var branch string
    err := row.Scan(&branch)
    if err == sql.ErrNoRows {
        return "", false
    }
    if err != nil {
        return "", false
    }
    return branch, true
}

func (ak *agentsKeeper) getAgentDict(agentID string, withTags bool) map[string]interface{} {
    if ak.db == nil {
        return nil
    }
    row := ak.db.QueryRow(`SELECT agent_id, branch, descr, location, extra FROM Agents WHERE agent_id = ?`, agentID)
    var descr, location, branch, extra string
    if err := row.Scan(&agentID, &branch, &descr, &location, &extra); err != nil {
        return nil
    }

    ret := map[string]interface{}{
        "agent_id": agentID,
        "branch":   branch,
        "descr":    descr,
        "location": location,
        "extra":    extra,
    }

    if withTags {
        rows, err := ak.db.Query(`SELECT tag FROM Tags WHERE agent_id = ?`, agentID)
        if err == nil {
            defer rows.Close()
            tags := []string{}
            for rows.Next() {
                var t string
                if err := rows.Scan(&t); err == nil {
                    tags = append(tags, t)
                }
            }
            ret["tags"] = tags
        }
    }
    return ret
}

func (ak *agentsKeeper) addAgent(agentID, branch, descr, location, extra string, tags []string) error {
    if ak.db == nil {
        return fmt.Errorf("database is not initialized")
    }
    tx, err := ak.db.Begin()
    if err != nil {
        return err
    }
    if _, err := tx.Exec(`INSERT INTO Agents (agent_id, branch, descr, location, extra) VALUES (?, ?, ?, ?, ?)`, agentID, branch, descr, location, extra); err != nil {
        _ = tx.Rollback()
        return err
    }
    for _, t := range tags {
        if t == "" {
            continue
        }
        if _, err := tx.Exec(`INSERT INTO Tags (agent_id, tag) VALUES (?, ?)`, agentID, t); err != nil {
            _ = tx.Rollback()
            return err
        }
    }
    return tx.Commit()
}

func (ak *agentsKeeper) deleteAgent(agentID string) error {
    if ak.db == nil {
        return fmt.Errorf("database not initialized")
    }
    tx, err := ak.db.Begin()
    if err != nil {
        return err
    }
    if _, err := tx.Exec(`DELETE FROM Tags WHERE agent_id = ?`, agentID); err != nil {
        _ = tx.Rollback()
        return err
    }
    res, err := tx.Exec(`DELETE FROM Agents WHERE agent_id = ?`, agentID)
    if err != nil {
        _ = tx.Rollback()
        return err
    }
    affected, _ := res.RowsAffected()
    if err := tx.Commit(); err != nil {
        return err
    }
    if affected == 0 {
        return fmt.Errorf("agent not found")
    }
    return nil
}

func (ak *agentsKeeper) getAgentsByBranches(branchNames []string) [][2]string {
    if ak.db == nil || len(branchNames) == 0 {
        return [][2]string{}
    }

    placeholders := make([]string, len(branchNames))
    args := make([]interface{}, len(branchNames))
    for i, b := range branchNames {
        placeholders[i] = "?"
        args[i] = b
    }
    q := "SELECT agent_id, branch FROM Agents WHERE branch IN (" + strings.Join(placeholders, ",") + ")"
    rows, err := ak.db.Query(q, args...)
    if err != nil {
        return [][2]string{}
    }
    defer rows.Close()

    out := make([][2]string, 0)
    for rows.Next() {
        var agentID, branch string
        if err := rows.Scan(&agentID, &branch); err == nil {
            out = append(out, [2]string{agentID, branch})
        }
    }
    return out
}
