package main

import (
    "bytes"
    "encoding/xml"
    "fmt"
    "os"
    "path/filepath"
    "sort"
    "strconv"
    "strings"
    "time"

    "github.com/antchfx/xmlquery"
)

type internError struct {
    dict4api map[string]interface{}
}

func (e *internError) Error() string {
    if e == nil || e.dict4api == nil {
        return ""
    }
    return fmt.Sprintf("%v", e.dict4api["warning"])
}

func newInternError(reason, warnmessage string, extras map[string]interface{}) *internError {
    ret := map[string]interface{}{"result": false, "reason": reason, "warning": warnmessage}
    for k, v := range extras {
        ret[k] = v
    }
    return &internError{dict4api: ret}
}

type configDataKeeper struct {
    filename     string
    cFilename    string
    dfltSessMax  int64
    xmlstorage   *xmlquery.Node
    xmlcats      *xmlquery.Node
    agentsKeeper *agentsKeeper
}

func newConfigDataKeeper(dataCatalogue string, defaultSessMax int64) *configDataKeeper {
    return &configDataKeeper{
        filename:     filepath.Join(dataCatalogue, "universe.xml"),
        cFilename:    filepath.Join(dataCatalogue, "catalogues.xml"),
        dfltSessMax:  defaultSessMax,
        agentsKeeper: newAgentsKeeper(dataCatalogue),
    }
}

func (dk *configDataKeeper) load() error {
    uxml, err := loadXMLFile(dk.filename)
    if err != nil {
        return err
    }
    dk.xmlstorage = uxml

    cxml, err := loadXMLFile(dk.cFilename)
    if err != nil {
        return err
    }
    dk.xmlcats = cxml

    return dk.agentsKeeper.initData()
}

func loadXMLFile(filename string) (*xmlquery.Node, error) {
    raw, err := os.ReadFile(filename)
    if err != nil {
        return nil, err
    }
    raw = bytes.TrimPrefix(raw, []byte{0xEF, 0xBB, 0xBF})
    return xmlquery.Parse(bytes.NewReader(raw))
}

func writeXMLToFile(filename string, node *xmlquery.Node) error {
    if node == nil {
        return fmt.Errorf("XML node is nil")
    }

    tempFilename := filename + ".temp.xml"
    backupFilename := filename + ".bk.xml"
    payload := []byte(node.OutputXML(true))

    if err := os.WriteFile(tempFilename, payload, 0o644); err != nil {
        return err
    }

    if _, err := os.Stat(filename); err == nil {
        if err := os.Rename(filename, backupFilename); err != nil {
            return err
        }
    }

    return os.Rename(tempFilename, filename)
}

func (dk *configDataKeeper) _save(catalogues bool) {
    if catalogues {
        _ = writeXMLToFile(dk.cFilename, dk.xmlcats)
    } else {
        _ = writeXMLToFile(dk.filename, dk.xmlstorage)
    }
}

func queryOne(top *xmlquery.Node, expr string) *xmlquery.Node {
    if top == nil {
        return nil
    }
    return xmlquery.FindOne(top, expr)
}

func queryAll(top *xmlquery.Node, expr string) []*xmlquery.Node {
    if top == nil {
        return nil
    }
    return xmlquery.Find(top, expr)
}

func parseIntAttr(node *xmlquery.Node, key string, fallback int64) int64 {
    if node == nil {
        return fallback
    }
    raw := node.SelectAttr(key)
    if raw == "" {
        return fallback
    }
    val, err := strconv.ParseInt(raw, 10, 64)
    if err != nil {
        return fallback
    }
    return val
}

func parseIntAttrInt(node *xmlquery.Node, key string, fallback int) int {
    return int(parseIntAttr(node, key, int64(fallback)))
}

func intListToInterface(values []string) []interface{} {
    out := make([]interface{}, 0, len(values))
    for _, value := range values {
        out = append(out, value)
    }
    return out
}

func sortedSet(set map[string]struct{}) []string {
    vals := make([]string, 0, len(set))
    for v := range set {
        vals = append(vals, v)
    }
    sort.Strings(vals)
    return vals
}

func addChildElement(parent *xmlquery.Node, name string, attrs map[string]string, text string) *xmlquery.Node {
    child := &xmlquery.Node{Type: xmlquery.ElementNode, Data: name}
    for key, val := range attrs {
        if val != "" {
            child.SetAttr(key, val)
        }
    }
    if text != "" {
        xmlquery.AddChild(child, &xmlquery.Node{Type: xmlquery.TextNode, Data: text})
    }
    xmlquery.AddChild(parent, child)
    return child
}

func firstElement(node *xmlquery.Node) *xmlquery.Node {
    for n := node.FirstChild; n != nil; n = n.NextSibling {
        if n.Type == xmlquery.ElementNode {
            return n
        }
    }
    return nil
}

func extractValue(n *xmlquery.Node, expr string) string {
    if n == nil {
        return ""
    }
    target := queryOne(n, expr)
    if target == nil {
        return ""
    }

    if target.Type == xmlquery.AttributeNode {
        return strings.TrimSpace(target.InnerText())
    }
    if target.Type == xmlquery.ElementNode {
        inner := target.InnerText()
        if inner != "" {
            return strings.TrimSpace(inner)
        }
    }
    if target.Type == xmlquery.TextNode || target.Type == xmlquery.CharDataNode {
        return strings.TrimSpace(target.Data)
    }
    return strings.TrimSpace(target.InnerText())
}

func (dk *configDataKeeper) _getUserNode(userid string) *xmlquery.Node {
    safeID, err := safeXPathValue(userid)
    if err != nil {
        return nil
    }
    expr := fmt.Sprintf("/universe/registers/people_register/person[@id='%s']", safeID)
    return queryOne(dk.xmlstorage, expr)
}

func (dk *configDataKeeper) _procFailure(unode *xmlquery.Node, failures int64, warntext string) {
    if unode == nil {
        return
    }
    unode.SetAttr("failures", strconv.FormatInt(failures, 10))
    unode.SetAttr("last_error", strconv.FormatInt(time.Now().Unix(), 10))
    dk._save(false)
}

func (dk *configDataKeeper) _reviewFunc4thePage(fi string) map[string]string {
    tmp := dk.reviewFunctions("id,name,title", fi)
    if tmp == nil || !tmp["result"].(bool) {
        return map[string]string{
            "id":    fi,
            "name":  "UNDESCRIBED " + fi,
            "title": "UNDESCRIBED " + fi,
        }
    }

    props, ok := tmp["props"].(map[string]interface{})
    if !ok {
        return map[string]string{
            "id":    fi,
            "name":  "UNDESCRIBED " + fi,
            "title": "UNDESCRIBED " + fi,
        }
    }
    name, _ := props["name"].(string)
    title, _ := props["title"].(string)
    if name == "" {
        name = "UNDESCRIBED " + fi
    }
    if title == "" {
        title = "UNDESCRIBED " + fi
    }
    return map[string]string{
        "id":    fi,
        "name":  name,
        "title": title,
    }
}

func (dk *configDataKeeper) _add_app_details(ret map[string]interface{}, appName string, userid string) map[string]interface{} {
    ret["for_application"] = appName

    if appName == "gAP" {
        ret["branches"] = dk.userBranches(userid)
        ret["positions"] = dk.userPositions(userid)
        ret["func_groups"] = dk._userFuncSets(userid)

        funcs := []interface{}{}
        for _, fi := range dk.__empFunctionIds(userid) {
            tmp := dk.reviewFunctions("id,callpath,method", fi)
            if tmp != nil && tmp["result"].(bool) {
                if p, ok := tmp["props"].(map[string]interface{}); ok {
                    funcs = append(funcs, p)
                }
            }
        }
        ret["functions"] = funcs

        if branches, ok := ret["branches"].([]string); ok && len(branches) > 0 {
            ret["agents"] = dk.listAgents(branches[0], true, false)["report"]
        } else {
            ret["agents"] = []interface{}{}
        }

        return ret
    }

    if appName == "thePage" {
        funcsets := dk._userFuncSets(userid)
        reports := map[string]interface{}{}
        for _, fsID := range funcsets {
            fsDet := dk.getFuncsetDetails(fsID)
            if fsDet == nil || !fsDet["result"].(bool) {
                continue
            }

            funcs := []interface{}{}
            if fset, ok := fsDet["functions"].([]string); ok {
                for _, fnID := range fset {
                    funcs = append(funcs, dk._reviewFunc4thePage(fnID))
                }
            }
            reports[fsID] = map[string]interface{}{
                "name":      fsDet["name"],
                "functions": funcs,
            }
        }
        ret["funcsets"] = reports
    }

    return ret
}

func (dk *configDataKeeper) get_user_reg_details(userid, appName string) map[string]interface{} {
    if userid == "" {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Not all required parameters are given: user id %v", userid), nil).dict4api
    }

    unode := dk._getUserNode(userid)
    if unode == nil {
        return newInternError("USER-UNKNOWN", fmt.Sprintf("User '%s' is unknown", userid), nil).dict4api
    }

    sessMax := dk.dfltSessMax
    if raw := unode.SelectAttr("sessionMax"); raw != "" {
        if parsed, err := strconv.ParseInt(raw, 10, 64); err == nil {
            sessMax = parsed
        }
    }

    ret := map[string]interface{}{
        "result":            true,
        "secret_changed":    parseIntAttr(unode, "pswChangedAt", 0),
        "secret_expiration": parseIntAttr(unode, "expireAt", 0),
        "readable_name":     unode.SelectAttr("readableName"),
        "session_max":       sessMax,
        "created":           []string{unode.SelectAttr("createdBy"), unode.SelectAttr("createdAt")},
        "change_history":     []interface{}{},
    }

    for _, ch := range queryAll(unode, "changed") {
        ret["change_history"] = append(ret["change_history"].([]interface{}), []string{ch.SelectAttr("by"), ch.SelectAttr("at")})
    }

    if appName != "" {
        dk._add_app_details(ret, appName, userid)
    }

    return ret
}

func (dk *configDataKeeper) authorize(userid, secret, appName string) map[string]interface{} {
    if secret == "" {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Not all required parameters are given: secret is %v", secret), nil).dict4api
    }

    ret := dk.get_user_reg_details(userid, appName)
    if ret == nil || !ret["result"].(bool) {
        return ret
    }

    unode := dk._getUserNode(userid)
    if unode == nil {
        return ret
    }

    failures := parseIntAttr(unode, "failures", 0)
    if unode.SelectAttr("secret") != secret {
        failures++
        dk._procFailure(unode, failures, fmt.Sprintf("User '%s' made %d password mistake(s)", userid, failures))
        return map[string]interface{}{"result": false, "reason": "WRONG-SECRET", "failures": failures}
    }

    expireTime := parseIntAttr(unode, "expireAt", 0)
    now := time.Now().Unix()
    if expireTime > 0 && now > expireTime {
        failures++
        dk._procFailure(unode, failures, fmt.Sprintf("Password of '%s' expired at %s, failures counter is %d", time.Unix(expireTime, 0).Format(time.RFC1123), failures))
        return map[string]interface{}{
            "result":            false,
            "reason":            "SECRET-EXPIRED",
            "secret_expiration": expireTime,
            "failures":          failures,
        }
    }

    unode.SetAttr("failures", "0")
    unode.SetAttr("last_auth_success", strconv.FormatInt(now, 10))
    dk._save(false)

    return ret
}

func (dk *configDataKeeper) getFuncsets() []string {
    values := make([]string, 0)
    for _, node := range queryAll(dk.xmlstorage, "//branch/deffuncsets/funcset") {
        if v := node.SelectAttr("id"); v != "" {
            values = append(values, v)
        }
    }
    return uniqueStrings(values)
}

func (dk *configDataKeeper) funcsetCreate(branchID, funcsetID, readableName string) map[string]interface{} {
    if branchID == "" {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Required argument not given: funcset is %v", funcsetID), nil).dict4api
    }

    branchNode, err := dk._getBranchNodeS(branchID, "deffuncsets", false)
    if err != nil {
        return err.dict4api
    }

    if funcsetID == "" {
        return newInternError("WRONG-FORMAT", "Required argument not given: funcset is ''", nil).dict4api
    }

    safeID, err2 := safeXPathValue(funcsetID)
    if err2 != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Required argument not given: funcset is %v", funcsetID), nil).dict4api
    }

    if len(queryAll(dk.xmlstorage, fmt.Sprintf("//branch/deffuncsets/funcset[@id='%s']", safeID))) > 0 {
        return newInternError("ALREADY-EXISTS", fmt.Sprintf("Funcset %v already defined somewhere", safeID), map[string]interface{}{"bad_value": safeID}).dict4api
    }

    fsNode := addChildElement(branchNode, "funcset", map[string]string{"id": safeID}, "")
    if readableName != "" {
        fsNode.SetAttr("name", readableName)
    }

    dk._save(false)
    return map[string]interface{}{"result": true}
}

func (dk *configDataKeeper) _getFsNode(funcsetID string, expectFunc bool, funcID string) (*xmlquery.Node, *internError) {
    if funcsetID == "" {
        return nil, newInternError("WRONG-FORMAT", "Required funcset id is not given", nil)
    }

    if expectFunc && funcID == "" {
        return nil, newInternError("WRONG-FORMAT", "Required function name is not given", nil)
    }

    safeFs, err := safeXPathValue(funcsetID)
    if err != nil {
        return nil, newInternError("WRONG-FORMAT", fmt.Sprintf("Required funcset id is unsafe %v", funcsetID), nil)
    }

    fsNodes := queryAll(dk.xmlstorage, fmt.Sprintf("//branch/deffuncsets/funcset[@id='%s']", safeFs))
    if len(fsNodes) == 0 {
        return nil, newInternError("FUNCSET-UNKNOWN", fmt.Sprintf("Funcset %v is unknown", safeFs), map[string]interface{}{"bad_value": safeFs})
    }
    return fsNodes[0], nil
}

func (dk *configDataKeeper) funcsetDelete(funcsetID string) map[string]interface{} {
    fsNode, err := dk._getFsNode(funcsetID, false, "")
    if err != nil {
        return err.dict4api
    }
    fsNode.RemoveFromTree()
    dk._save(false)
    return map[string]interface{}{"result": true}
}

func (dk *configDataKeeper) getFuncsetDetails(funcsetID string) map[string]interface{} {
    fsNode, err := dk._getFsNode(funcsetID, false, "")
    if err != nil {
        return err.dict4api
    }

    funcIDs := make([]string, 0)
    for _, node := range queryAll(fsNode, "func") {
        if v := node.SelectAttr("id"); v != "" {
            funcIDs = append(funcIDs, v)
        }
    }

    return map[string]interface{}{
        "result":    true,
        "functions": funcIDs,
        "name":      fsNode.SelectAttr("name"),
        "id":        funcsetID,
    }
}

func (dk *configDataKeeper) funcsetFuncAdd(funcsetID, funcID string) map[string]interface{} {
    fsNode, err := dk._getFsNode(funcsetID, true, funcID)
    if err != nil {
        return err.dict4api
    }

    safeFuncID, err2 := safeXPathValue(funcID)
    if err2 != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Required function name is unsafe %v", funcID), nil).dict4api
    }

    if len(queryAll(fsNode, fmt.Sprintf("func[@id='%s']", safeFuncID))) > 0 {
        return newInternError("ALREADY-EXISTS", fmt.Sprintf("Function %v already in %v", safeFuncID, funcsetID), map[string]interface{}{"bad_value": safeFuncID}).dict4api
    }

    addChildElement(fsNode, "func", map[string]string{"id": safeFuncID}, "")
    dk._save(false)
    return map[string]interface{}{"result": true}
}

func (dk *configDataKeeper) funcsetFuncRemove(funcsetID, funcID string) map[string]interface{} {
    fsNode, err := dk._getFsNode(funcsetID, true, funcID)
    if err != nil {
        return err.dict4api
    }

    safeFuncID, err2 := safeXPathValue(funcID)
    if err2 != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Required function name is unsafe %v", funcID), nil).dict4api
    }

    fnNodes := queryAll(fsNode, fmt.Sprintf("func[@id='%s']", safeFuncID))
    if len(fnNodes) == 0 {
        return newInternError("NOT-IN-SET", fmt.Sprintf("Function %v is not in %v", safeFuncID, funcsetID), map[string]interface{}{"bad_value": safeFuncID}).dict4api
    }
    fnNodes[0].RemoveFromTree()
    dk._save(false)
    return map[string]interface{}{"result": true}
}

func (dk *configDataKeeper) userBranches(userid string) []string {
    safeID, err := safeXPathValue(userid)
    if err != nil {
        return []string{}
    }

    branches := make([]string, 0)
    for _, br := range queryAll(dk.xmlstorage, fmt.Sprintf("//branch[employees/employee[@person='%s']]", safeID)) {
        if v := br.SelectAttr("id"); v != "" {
            branches = append(branches, v)
        }
    }
    return uniqueStrings(branches)
}

func (dk *configDataKeeper) userPositions(userid string) []string {
    safeID, err := safeXPathValue(userid)
    if err != nil {
        return []string{}
    }

    pos := make([]string, 0)
    for _, employee := range queryAll(dk.xmlstorage, fmt.Sprintf("//employee[@person='%s']", safeID)) {
        if p := employee.SelectAttr("pos"); p != "" {
            pos = append(pos, p)
        }
    }
    return uniqueStrings(pos)
}

func (dk *configDataKeeper) listBranches() []string {
    vals := make([]string, 0)
    for _, branch := range queryAll(dk.xmlstorage, "//branch/@id") {
        if branch.Type == xmlquery.AttributeNode {
            vals = append(vals, branch.InnerText())
            continue
        }
        vals = append(vals, branch.Data)
    }
    ids := make([]string, 0)
    for _, node := range queryAll(dk.xmlstorage, "//branch") {
        if id := node.SelectAttr("id"); id != "" {
            ids = append(ids, id)
        }
    }
    return uniqueStrings(ids)
}

func (dk *configDataKeeper) listRoles4Branch(branchID string) []string {
    if branchID == "" {
        return []string{}
    }

    branchNode, err := dk._getBranchNodeS(branchID, "", false)
    if err != nil {
        return []string{}
    }

    ret := make([]string, 0)
    for _, node := range queryAll(branchNode, "roles/role/@name") {
        if node.Type == xmlquery.AttributeNode {
            ret = append(ret, node.InnerText())
            continue
        }
        ret = append(ret, strings.TrimSpace(node.Data))
    }

    ids := make([]string, 0)
    for _, node := range queryAll(branchNode, "roles/role") {
        if n := node.SelectAttr("name"); n != "" {
            ids = append(ids, n)
        }
    }
    return uniqueStrings(ids)
}

func (dk *configDataKeeper) _getRoleNode(branchID, roleName string) (*xmlquery.Node, *internError) {
    rolesNode, err := dk._getBranchNodeS(branchID, "roles", false)
    if err != nil {
        return nil, err
    }

    safeRole, err2 := safeXPathValue(roleName)
    if err2 != nil {
        return nil, newInternError("WRONG-FORMAT", fmt.Sprintf("Required argument not given: role is %v", roleName), nil)
    }

    roleNodes := queryAll(rolesNode, fmt.Sprintf("role[@name='%s']", safeRole))
    if len(roleNodes) == 0 {
        return nil, newInternError("ROLE-UNKNOWN", fmt.Sprintf("Role %v not defined in branch %v", roleName, branchID), nil)
    }
    return roleNodes[0], nil
}

func (dk *configDataKeeper) listRoleFuncsets(branchID, roleName string) map[string]interface{} {
    roleNode, err := dk._getRoleNode(branchID, roleName)
    if err != nil {
        return err.dict4api
    }

    funcsets := make([]string, 0)
    for _, fs := range queryAll(roleNode, "funcset/@id") {
        if fs.Type == xmlquery.AttributeNode {
            funcsets = append(funcsets, fs.InnerText())
            continue
        }
        if id := fs.SelectAttr("id"); id != "" {
            funcsets = append(funcsets, id)
        }
    }

    return map[string]interface{}{"result": true, "funcsets": uniqueStrings(funcsets)}
}

func (dk *configDataKeeper) roleFuncsetAdd(branchID, roleName, funcsetID string) map[string]interface{} {
    roleNode, err := dk._getRoleNode(branchID, roleName)
    if err != nil {
        return err.dict4api
    }

    if len(queryAll(roleNode, fmt.Sprintf("funcset[@id='%s']", funcsetID))) > 0 {
        return newInternError("ALREADY-EXISTS", fmt.Sprintf("Funcset %v already in role %v of %v", funcsetID, roleName, branchID), nil).dict4api
    }

    addChildElement(roleNode, "funcset", map[string]string{"id": funcsetID}, "")
    dk._save(false)
    return map[string]interface{}{"result": true}
}

func (dk *configDataKeeper) roleFuncsetRemove(branchID, roleName, funcsetID string) map[string]interface{} {
    roleNode, err := dk._getRoleNode(branchID, roleName)
    if err != nil {
        return err.dict4api
    }

    fsNodes := queryAll(roleNode, fmt.Sprintf("funcset[@id='%s']", funcsetID))
    if len(fsNodes) == 0 {
        return newInternError("NOT-IN-SET", fmt.Sprintf("Funcset %v is not in role %v of %v", funcsetID, roleName, branchID), nil).dict4api
    }

    fsNodes[0].RemoveFromTree()
    dk._save(false)
    return map[string]interface{}{"result": true}
}

func (dk *configDataKeeper) reviewBranches(pos string) []interface{} {
    safePos, err := safeXPathValue(pos)
    if err != nil {
        safePos = ""
    }

    ret := make([]interface{}, 0)
    for _, br := range queryAll(dk.xmlstorage, "//branch") {
        if safePos != "" {
            hasPos := false
            for _, emp := range queryAll(br, "employees/employee") {
                if emp.SelectAttr("pos") == safePos {
                    hasPos = true
                    break
                }
            }
            if !hasPos {
                continue
            }
        }

        vacancies := make([]string, 0)
        for _, emp := range queryAll(br, "employees/employee") {
            if emp.SelectAttr("person") != "" {
                continue
            }

            p := emp.SelectAttr("pos")
            if safePos != "" && br.SelectAttr("pos") != "" && br.SelectAttr("pos") != safePos {
                continue
            }
            if safePos != "" && p != safePos {
                continue
            }
            if p != "" {
                vacancies = append(vacancies, p)
            }
        }

        ret = append(ret, map[string]interface{}{
            "id":        br.SelectAttr("id"),
            "vacancies": uniqueStrings(vacancies),
        })
    }
    return ret
}

func (dk *configDataKeeper) getBranches(pos string) []interface{} {
    safePos, err := safeXPathValue(pos)
    if err != nil {
        safePos = ""
    }

    ret := make([]interface{}, 0)
    for _, br := range queryAll(dk.xmlstorage, "//branch") {
        if safePos != "" {
            hasPos := false
            for _, emp := range queryAll(br, "employees/employee") {
                if emp.SelectAttr("pos") == safePos {
                    hasPos = true
                    break
                }
            }
            if !hasPos {
                continue
            }
        }

        value := 0
        for _, emp := range queryAll(br, "employees/employee") {
            if emp.SelectAttr("person") != "" {
                continue
            }
            if safePos != "" {
                if br.SelectAttr("pos") != "" && br.SelectAttr("pos") != safePos {
                    continue
                }
                if emp.SelectAttr("pos") != safePos {
                    continue
                }
            }
            value++
        }

        ret = append(ret, map[string]interface{}{
            "id":    br.SelectAttr("id"),
            "value": fmt.Sprintf("%s - %d vacancies", br.SelectAttr("id"), value),
        })
    }
    return ret
}

func (dk *configDataKeeper) getBranchSubs(branchID string) map[string]interface{} {
    var root *xmlquery.Node
    if branchID == "" {
        root = dk.xmlstorage
    } else {
        br, err := dk._getBranchNodeS(branchID, "", false)
        if err != nil {
            return err.dict4api
        }
        root = br
    }

    ids := make([]string, 0)
    for _, node := range queryAll(root, "descendant::branch/@id") {
        if node.Type == xmlquery.AttributeNode {
            ids = append(ids, node.InnerText())
            continue
        }
        if v := node.SelectAttr("id"); v != "" {
            ids = append(ids, v)
        }
    }

    return map[string]interface{}{"result": true, "branches": uniqueStrings(ids)}
}

func (dk *configDataKeeper) addBranchSub(branchID, subID string) map[string]interface{} {
    branchesNode, err := dk._getBranchNodeS(branchID, "branches", false)
    if err != nil {
        return err.dict4api
    }

    if subID == "" {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Required argument not given: subbranch is %v", subID), nil).dict4api
    }

    safeSub, err2 := safeXPathValue(subID)
    if err2 != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Required argument not given: subbranch is %v", subID), nil).dict4api
    }

    if len(queryAll(branchesNode, fmt.Sprintf("branch[@id='%s']", safeSub))) > 0 {
        return newInternError("ALREADY-EXISTS", fmt.Sprintf("Branch %v already has subbranch %v", branchID, safeSub), map[string]interface{}{"bad_value": safeSub}).dict4api
    }

    brNode := addChildElement(branchesNode, "branch", map[string]string{"id": safeSub}, "")
    addChildElement(brNode, "func_white_list", map[string]string{"propagateParent": "no"}, "")
    addChildElement(brNode, "employees", nil, "")
    addChildElement(brNode, "roles", nil, "")
    addChildElement(brNode, "deffuncsets", nil, "")
    addChildElement(brNode, "branches", nil, "")

    dk._save(false)
    return map[string]interface{}{"result": true}
}

func (dk *configDataKeeper) deleteBranch(branchID string) map[string]interface{} {
    branchNode, err := dk._getBranchNodeS(branchID, "", false)
    if err != nil {
        return err.dict4api
    }

    if len(queryAll(branchNode, "ancestor::branch")) == 0 {
        return newInternError("NOT-ALLOWED", fmt.Sprintf("Deletion of a root branch %v is not allowed", branchID), map[string]interface{}{"bad_value": branchID}).dict4api
    }

    if employed := queryAll(branchNode, "descendant::employee[@person]"); len(employed) > 0 {
        employedUsers := make([]string, 0)
        for _, emp := range employed {
            p := emp.SelectAttr("person")
            if p != "" {
                employedUsers = append(employedUsers, p)
            }
        }
        return newInternError("USER-EMPLOYED", fmt.Sprintf("Branch %v still has employees: %v", branchID, employedUsers), map[string]interface{}{"fire_them": uniqueStrings(employedUsers)}).dict4api
    }

    branchNode.RemoveFromTree()
    dk._save(false)
    return map[string]interface{}{"result": true}
}

func (dk *configDataKeeper) getBranchFsWhiteList(branchID string) map[string]interface{} {
    wlNode, err := dk._getBranchNodeS(branchID, "func_white_list", false)
    if err != nil {
        return err.dict4api
    }

    funcsets := make([]string, 0)
    for _, fs := range queryAll(wlNode, "funcset/@id") {
        if fs.Type == xmlquery.AttributeNode {
            funcsets = append(funcsets, fs.InnerText())
            continue
        }
        if v := fs.SelectAttr("id"); v != "" {
            funcsets = append(funcsets, v)
        }
    }

    return map[string]interface{}{
        "result":             true,
        "funcsets":           uniqueStrings(funcsets),
        "propagate_parent_flag": strings.ToLower(wlNode.SelectAttr("propagateParent")) == "yes",
    }
}

func (dk *configDataKeeper) setBranchFsWhiteList(branchID string, propParentFlag bool, newwlist []string) map[string]interface{} {
    wlNode, err := dk._getBranchNodeS(branchID, "func_white_list", false)
    if err != nil {
        return err.dict4api
    }

    wlNode.SetAttr("propagateParent", boolToYesNo(propParentFlag))
    for _, old := range queryAll(wlNode, "funcset") {
        old.RemoveFromTree()
    }

    for _, fs := range newwlist {
        fs = strings.TrimSpace(fs)
        if fs == "" {
            continue
        }
        addChildElement(wlNode, "funcset", map[string]string{"id": fs}, "")
    }

    dk._save(false)
    return map[string]interface{}{"result": true}
}

func boolToYesNo(v bool) string {
    if v {
        return "yes"
    }
    return "no"
}

func (dk *configDataKeeper) _getBranchNodeS(branchID string, subpath string, autocreate bool) (*xmlquery.Node, *internError) {
    if branchID == "" {
        return nil, newInternError("WRONG-FORMAT", fmt.Sprintf("Required argument not given: branch is %v", branchID), nil)
    }

    safeBranch, err := safeXPathValue(branchID)
    if err != nil {
        return nil, newInternError("WRONG-FORMAT", fmt.Sprintf("Required argument not given: branch is %v", branchID), nil)
    }

    brs := queryAll(dk.xmlstorage, fmt.Sprintf("//branch[@id='%s']", safeBranch))
    if len(brs) == 0 {
        return nil, newInternError("BRANCH-UNKNOWN", fmt.Sprintf("Branch %v is unknown", safeBranch), map[string]interface{}{"bad_value": safeBranch})
    }

    if subpath == "" {
        return brs[0], nil
    }

    subs := queryAll(brs[0], subpath)
    if len(subs) == 0 {
        if !autocreate {
            return nil, newInternError("DATABASE-ERROR", fmt.Sprintf("Inconsistent server data: branch %v description has no sub-path %v", safeBranch, subpath), map[string]interface{}{"inconsistence": subpath})
        }
        return addChildElement(brs[0], subpath, nil, ""), nil
    }
    return subs[0], nil
}

func (dk *configDataKeeper) listUsers() map[string]interface{} {
    users := make([]string, 0)
    for _, p := range queryAll(dk.xmlstorage, "/universe/registers/people_register/person/@id") {
        if p.Type == xmlquery.AttributeNode {
            users = append(users, p.InnerText())
        } else {
            users = append(users, p.SelectAttr("id"))
        }
    }
    return map[string]interface{}{
        "result": true,
        "users":  users,
    }
}

func (dk *configDataKeeper) reviewPositions(branchID string) []interface{} {
    if branchID == "" {
        branchID = ""
    }
    safeBranch, err := safeXPathValue(branchID)
    if err != nil {
        safeBranch = ""
    }

    selector := "//branch"
    if safeBranch != "" {
        selector = fmt.Sprintf("//branch[@id='%s']", safeBranch)
    }

    ret := make([]interface{}, 0)
    for _, branch := range queryAll(dk.xmlstorage, selector) {
        for _, e := range queryAll(branch, "employees/employee") {
            ret = append(ret, map[string]interface{}{
                "pos":   e.SelectAttr("pos"),
                "branch": branch.SelectAttr("id"),
                "vacant": e.SelectAttr("person") == "",
            })
        }
    }
    return ret
}

func (dk *configDataKeeper) getPositions(branchID string) []interface{} {
    if branchID == "" {
        branchID = ""
    }
    safeBranch, err := safeXPathValue(branchID)
    if err != nil {
        safeBranch = ""
    }

    selector := "//branch"
    if safeBranch != "" {
        selector = fmt.Sprintf("//branch[@id='%s']", safeBranch)
    }

    ret := make([]interface{}, 0)
    for _, branch := range queryAll(dk.xmlstorage, selector) {
        for _, e := range queryAll(branch, "employees/employee") {
            person := e.SelectAttr("person")
            state := "VACANT"
            if person != "" {
                state = "OCCUPIED"
            }
            ret = append(ret, map[string]interface{}{
                "id":    e.SelectAttr("pos"),
                "value": fmt.Sprintf("%s at %s %s", e.SelectAttr("pos"), branch.SelectAttr("id"), state),
            })
        }
    }
    return ret
}

func (dk *configDataKeeper) get_branches_with_positions(branchID string, perRole bool, onlyVacant bool) map[string]interface{} {
    if branchID != "*ALL*" {
        safeBranch, err := safeXPathValue(branchID)
        if err != nil {
            return newInternError("WRONG-FORMAT", fmt.Sprintf("Branch %v is unsafe", branchID), nil).dict4api
        }
        branchID = safeBranch
    }

    var roots []*xmlquery.Node
    if branchID == "*ALL*" {
        roots = queryAll(dk.xmlstorage, "//branch")
    } else {
        if b := queryOne(dk.xmlstorage, fmt.Sprintf("//branch[@id='%s']", branchID)); b != nil {
            roots = queryAll(b, "descendant-or-self::branch")
        }
    }
	if len(roots) == 0 {
		return map[string]interface{}{
			"result":      true,
			"branch_filter": branchID,
			"only_vacant": onlyVacant,
			"report":      []interface{}{},
		}
	}

    report := make([]interface{}, 0)
    for _, br := range roots {
        countAll := 0
        for _, e := range queryAll(br, "employees/employee") {
            if onlyVacant && e.SelectAttr("person") != "" {
                continue
            }
            countAll++
        }

        if !perRole {
            report = append(report, map[string]interface{}{
                "branch": br.SelectAttr("id"),
                "count":  countAll,
            })
            continue
        }

        positions := make([]string, 0)
        for _, e := range queryAll(br, "employees/employee") {
            if onlyVacant && e.SelectAttr("person") != "" {
                continue
            }
            positions = append(positions, e.SelectAttr("pos"))
        }

        for _, p := range uniqueStrings(positions) {
            cnt := 0
            for _, e := range queryAll(br, fmt.Sprintf("employees/employee[@pos='%s']", p)) {
                if onlyVacant && e.SelectAttr("person") != "" {
                    continue
                }
                cnt++
            }
            report = append(report, map[string]interface{}{
                "branch": br.SelectAttr("id"),
                "role":   p,
                "count":  cnt,
            })
        }
    }

    return map[string]interface{}{
        "result":      true,
        "branch_filter": branchID,
        "only_vacant": onlyVacant,
        "report":      report,
    }
}

func (dk *configDataKeeper) _collectBranchFuncsets(branchNode *xmlquery.Node) map[string]struct{} {
    if branchNode == nil {
        return map[string]struct{}{}
    }

    ret := map[string]struct{}{}
    for _, fs := range queryAll(branchNode, "deffuncsets/funcset") {
        if fsid := fs.SelectAttr("id"); fsid != "" {
            ret[fsid] = struct{}{}
        }
    }

    wlNodes := queryAll(branchNode, "func_white_list")
    anc := queryAll(branchNode, "ancestor::branch")
    if len(wlNodes) == 0 || len(anc) == 0 {
        return ret
    }

    parent := anc[len(anc)-1]
    parentFuncsets := dk._collectBranchFuncsets(parent)

    if strings.ToLower(wlNodes[0].SelectAttr("propagateParent")) == "yes" {
        return mergeSets(ret, parentFuncsets)
    }

    wl := map[string]struct{}{}
    for _, fs := range queryAll(wlNodes[0], "funcset") {
        if id := fs.SelectAttr("id"); id != "" {
            wl[id] = struct{}{}
        }
    }

    return mergeSets(ret, intersectMaps(parentFuncsets, wl))
}

func mergeSets(a, b map[string]struct{}) map[string]struct{} {
    ret := map[string]struct{}{}
    for k := range a {
        ret[k] = struct{}{}
    }
    for k := range b {
        ret[k] = struct{}{}
    }
    return ret
}

func intersectMaps(a, b map[string]struct{}) map[string]struct{} {
    ret := map[string]struct{}{}
    for k := range a {
        if _, ok := b[k]; ok {
            ret[k] = struct{}{}
        }
    }
    return ret
}

func (dk *configDataKeeper) _findRoleNode(pos string, branchNode *xmlquery.Node) *xmlquery.Node {
    if branchNode == nil {
        return nil
    }

    safePos, err := safeXPathValue(pos)
    if err != nil {
        return nil
    }

    candidates := queryAll(branchNode, fmt.Sprintf("ancestor-or-self::branch/roles/role[@name='%s']", safePos))
    if len(candidates) == 0 {
        return nil
    }
    return candidates[len(candidates)-1]
}

func (dk *configDataKeeper) listEnabledRoles4Branch(branchID string) []string {
    branchNode, err := dk._getBranchNodeS(branchID, "", false)
    if err != nil {
        return []string{}
    }

    set := map[string]struct{}{}
    for _, role := range queryAll(branchNode, "ancestor-or-self::branch/roles/role/@name") {
        if role.Type == xmlquery.AttributeNode {
            set[strings.TrimSpace(role.InnerText())] = struct{}{}
        } else {
            if n := role.SelectAttr("name"); n != "" {
                set[n] = struct{}{}
            }
        }
    }
    return sortedSet(set)
}

func (dk *configDataKeeper) createBranchPosition(branchID, roleName string) map[string]interface{} {
    empsNode, err := dk._getBranchNodeS(branchID, "employees", false)
    if err != nil {
        return err.dict4api
    }

    safeRole, err2 := safeXPathValue(roleName)
    if err2 != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Required argument not given: role is %v", roleName), nil).dict4api
    }

    empNode := addChildElement(empsNode, "employee", map[string]string{"pos": safeRole}, "")
    _ = empNode
    total := len(queryAll(empsNode, fmt.Sprintf("employee[@pos='%s']", safeRole)))
    vacant := 0
    for _, e := range queryAll(empsNode, fmt.Sprintf("employee[@pos='%s' and not(@person)]", safeRole)) {
        if e.SelectAttr("person") == "" {
            vacant++
        }
    }

    dk._save(false)
    return map[string]interface{}{
        "result": true,
        "branch": branchID,
        "pos":    roleName,
        "total":  total,
        "vacant": vacant,
    }
}

func (dk *configDataKeeper) deleteBranchPosition(branchID, roleName string) map[string]interface{} {
    empsNode, err := dk._getBranchNodeS(branchID, "employees", false)
    if err != nil {
        return err.dict4api
    }

    safeRole, err2 := safeXPathValue(roleName)
    if err2 != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Required argument not given: role is %v", roleName), nil).dict4api
    }

    candidates := queryAll(empsNode, fmt.Sprintf("employee[@pos='%s' and not(@person)]", safeRole))
    if len(candidates) == 0 {
        return newInternError("NOT-IN-SET", fmt.Sprintf("Branch %v has no vacant %v positions", branchID, roleName), nil).dict4api
    }
    candidates[len(candidates)-1].RemoveFromTree()

    total := len(queryAll(empsNode, fmt.Sprintf("employee[@pos='%s']", safeRole)))
    vacant := 0
    for _, e := range queryAll(empsNode, fmt.Sprintf("employee[@pos='%s' and not(@person)]", safeRole)) {
        if e.SelectAttr("person") == "" {
            vacant++
        }
    }

    dk._save(false)
    return map[string]interface{}{
        "result": true,
        "branch": branchID,
        "pos":    roleName,
        "total":  total,
        "vacant": vacant,
    }
}

func (dk *configDataKeeper) getBranchVacantPositions(branchID string) []string {
    safeBranch, err := safeXPathValue(branchID)
    if err != nil {
        return []string{}
    }

    ret := make(map[string]struct{})
    for _, e := range queryAll(dk.xmlstorage, fmt.Sprintf("//branch[@id='%s']/employees/employee[not(@person)]/@pos", safeBranch)) {
        if e.Type == xmlquery.AttributeNode {
            ret[strings.TrimSpace(e.InnerText())] = struct{}{}
            continue
        }
        if p := e.SelectAttr("pos"); p != "" {
            ret[p] = struct{}{}
        }
    }

    return sortedSet(ret)
}

func (dk *configDataKeeper) _userFuncSets(userid string) []string {
    safeID, err := safeXPathValue(userid)
    if err != nil {
        return []string{}
    }

    empNodes := queryAll(dk.xmlstorage, fmt.Sprintf("//branch/employees/employee[@person='%s']", safeID))
    if len(empNodes) == 0 {
        return []string{}
    }

    branchNode := empNodes[0].Parent.Parent
    whitelist := dk._collectBranchFuncsets(branchNode)
    pos := empNodes[0].SelectAttr("pos")

    roleNode := dk._findRoleNode(pos, branchNode)
    if roleNode == nil {
        return []string{}
    }

    roleSets := map[string]struct{}{}
    for _, fs := range queryAll(roleNode, "funcset/@id") {
        if fs.Type == xmlquery.AttributeNode {
            roleSets[strings.TrimSpace(fs.InnerText())] = struct{}{}
            continue
        }
        if id := fs.SelectAttr("id"); id != "" {
            roleSets[id] = struct{}{}
        }
    }

    return sortedSet(intersectMaps(whitelist, roleSets))
}

func (dk *configDataKeeper) getBranchEnabledFuncsets(branchID string) []string {
    branchNode, err := dk._getBranchNodeS(branchID, "", false)
    if err != nil {
        return []string{}
    }
    return sortedSet(dk._collectBranchFuncsets(branchNode))
}

func (dk *configDataKeeper) listBranchRoles(branchID string, withInherited, withBranchIds bool) map[string]interface{} {
    branchNode, err := dk._getBranchNodeS(branchID, "", false)
    if err != nil {
        return err.dict4api
    }

    rolesSet := map[string]struct{}{}
    axis := "self"
    if withInherited {
        axis = "ancestor-or-self"
    }

    for _, role := range queryAll(branchNode, fmt.Sprintf("%s::branch/roles/role", axis)) {
        if role == nil {
            continue
        }
        if name := role.SelectAttr("name"); name != "" {
            rolesSet[name] = struct{}{}
        }
    }

    if !withBranchIds {
        return map[string]interface{}{"result": true, "roles": sortedSet(rolesSet)}
    }

    rolesInBranches := make([]interface{}, 0)
    for _, roleName := range sortedSet(rolesSet) {
        roleNode := dk._findRoleNode(roleName, branchNode)
        parentBranch := ""
        if roleNode != nil && roleNode.Parent != nil && roleNode.Parent.Parent != nil {
            parentBranch = roleNode.Parent.Parent.SelectAttr("id")
        }
        rolesInBranches = append(rolesInBranches, []interface{}{roleName, parentBranch})
    }

    return map[string]interface{}{
        "result":           true,
        "roles_in_branch": rolesInBranches,
    }
}

func (dk *configDataKeeper) createBranchRole(branchID, roleName string, duties []string) map[string]interface{} {
    rolesNode, err := dk._getBranchNodeS(branchID, "roles", false)
    if err != nil {
        return err.dict4api
    }

    safeRole, err2 := safeXPathValue(roleName)
    if err2 != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Required argument not given: role is %v", roleName), nil).dict4api
    }

    if len(queryAll(rolesNode, fmt.Sprintf("role[@name='%s']", safeRole))) > 0 {
        return newInternError("ALREADY-EXISTS", fmt.Sprintf("Role %v already defined in branch %v", roleName, branchID), map[string]interface{}{"bad_value": safeRole}).dict4api
    }

    roleNode := addChildElement(rolesNode, "role", map[string]string{"name": safeRole}, "")
    for _, d := range duties {
        d = strings.TrimSpace(d)
        if d == "" {
            continue
        }
        addChildElement(roleNode, "funcset", map[string]string{"id": d}, "")
    }

    dk._save(false)
    return map[string]interface{}{"result": true}
}

func (dk *configDataKeeper) deleteBranchRole(branchID, roleName string) map[string]interface{} {
    rolesNode, err := dk._getBranchNodeS(branchID, "roles", false)
    if err != nil {
        return err.dict4api
    }

    safeRole, err2 := safeXPathValue(roleName)
    if err2 != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Required argument not given: role is %v", roleName), nil).dict4api
    }

    roleNodes := queryAll(rolesNode, fmt.Sprintf("role[@name='%s']", safeRole))
    if len(roleNodes) == 0 {
        return newInternError("ROLE-UNKNOWN", fmt.Sprintf("Role %v has no direct definition in branch %v", roleName, branchID), map[string]interface{}{"bad_value": safeRole}).dict4api
    }

    roleNodes[0].RemoveFromTree()
    dk._save(false)
    return map[string]interface{}{"result": true}
}

func (dk *configDataKeeper) _get_operatorS_node(operatorID string) (*xmlquery.Node, *internError) {
    if operatorID == "" {
        return nil, newInternError("OP-UNAUTHORIZED", "Operator not authorized or authorization expired", nil)
    }
    opNode := dk._getUserNode(operatorID)
    if opNode == nil {
        return nil, newInternError("OP-UNKNOWN", fmt.Sprintf("Operator %v is unknown to the system", operatorID), nil)
    }
    return opNode, nil
}

func (dk *configDataKeeper) _get_operatorS_branch(operatorID string) (*xmlquery.Node, *internError) {
    _, err := safeXPathValue(operatorID)
    if err != nil {
        return nil, newInternError("WRONG-FORMAT", fmt.Sprintf("Operator identifier %v is unsafe", operatorID), nil)
    }

    opBranches := queryAll(dk.xmlstorage, fmt.Sprintf("//branch[employees/employee[@person='%s']]", operatorID))
    if len(opBranches) == 0 {
        return nil, newInternError("FORBIDDEN-FOR-OP", fmt.Sprintf("Operator %v is nowhere employed", operatorID), nil)
    }
    return opBranches[0], nil
}

func (dk *configDataKeeper) createUser(userid, secret, operator, pswLifeTime, readableName, sessionMax string) map[string]interface{} {
    if userid == "" || secret == "" || operator == "" {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Not all required parameters are given: user id:%v, secret:%v, operator:%v", userid, secret, operator), nil).dict4api
    }

    if dk._getUserNode(userid) != nil {
        return newInternError("ALREADY-EXISTS", fmt.Sprintf("User '%s' already exists", userid), nil).dict4api
    }

    if _, ex := dk._get_operatorS_node(operator); ex != nil {
        return ex.dict4api
    }

    pnodes := queryAll(dk.xmlstorage, "/universe/registers/people_register")
    if len(pnodes) == 0 {
        return newInternError("DATABASE-ERROR", "No people register found", nil).dict4api
    }

    pswTime := time.Now().Unix()
    unode := addChildElement(pnodes[0], "person", map[string]string{"id": userid, "secret": secret, "pswChangedAt": strconv.FormatInt(pswTime, 10), "failures": "0", "readableName": readableName, "sessionMax": strconv.FormatInt(toInt(sessionMax, int(dk.dfltSessMax)), 10), "createdBy": operator, "createdAt": strconv.FormatInt(pswTime, 10)}, "")

    ret := map[string]interface{}{"result": true, "secret_changed": pswTime}
    if pswLifeTime != "" {
        ttl, err := strconv.ParseFloat(pswLifeTime, 64)
        if err == nil {
            expTime := pswTime + int64(ttl*86400)
            unode.SetAttr("expireAt", strconv.FormatInt(expTime, 10))
            ret["secret_expiration"] = expTime
        }
    }

    dk._save(false)
    return ret
}

func (dk *configDataKeeper) changeUser(userid, secret, operator, pswLifeTime, readableName, sessionMax string) map[string]interface{} {
    if userid == "" || secret == "" || operator == "" {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Not all required parameters are given: user id:%v, secret:%v, operator:%v", userid, secret, operator), nil).dict4api
    }

    unode := dk._getUserNode(userid)
    if unode == nil {
        return newInternError("USER-UNKNOWN", fmt.Sprintf("User %v is unknown", userid), nil).dict4api
    }

    if _, ex := dk._get_operatorS_node(operator); ex != nil {
        return ex.dict4api
    }

    pswTime := time.Now().Unix()
    unode.SetAttr("secret", secret)
    unode.SetAttr("pswChangedAt", strconv.FormatInt(pswTime, 10))
    unode.SetAttr("readableName", readableName)
    unode.SetAttr("sessionMax", strconv.FormatInt(toInt(sessionMax, int(dk.dfltSessMax)), 10))
    unode.SetAttr("failures", "0")

    ret := map[string]interface{}{"result": true, "secret_changed": pswTime}
    if pswLifeTime != "" {
        ttl, err := strconv.ParseFloat(pswLifeTime, 64)
        if err == nil {
            expTime := pswTime + int64(ttl*86400)
            unode.SetAttr("expireAt", strconv.FormatInt(expTime, 10))
            ret["secret_expiration"] = expTime
        }
    } else if unode.SelectAttr("expireAt") != "" {
        unode.RemoveAttr("expireAt")
    }

    changedNode := addChildElement(unode, "changed", map[string]string{"by": operator, "at": strconv.FormatInt(pswTime, 10)}, "")
    _ = changedNode

    dk._save(false)
    return ret
}

func (dk *configDataKeeper) deleteUser(userid, operator string) map[string]interface{} {
    if _, ex := dk._get_operatorS_node(operator); ex != nil {
        return ex.dict4api
    }

    if userid == "" {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Not all required parameters are given: user id is %v", userid), nil).dict4api
    }

    unode := dk._getUserNode(userid)
    if unode == nil {
        return newInternError("USER-UNKNOWN", fmt.Sprintf("User %v is unknown", userid), nil).dict4api
    }

    if branches := dk.userBranches(userid); len(branches) != 0 {
        return newInternError("USER-EMPLOYED", fmt.Sprintf("User '%v' is employed, fire him first", userid), nil).dict4api
    }

    if unode.Parent != nil {
        unode.RemoveFromTree()
    }
    dk._save(false)
    return map[string]interface{}{"result": true}
}

func (dk *configDataKeeper) _get_empNode_relOp(operatorID, userid string) (*xmlquery.Node, *internError) {
    opBranch, ex := dk._get_operatorS_branch(operatorID)
    if ex != nil {
        return nil, ex
    }

    uid, err := safeXPathValue(userid)
    if err != nil {
        return nil, newInternError("WRONG-FORMAT", fmt.Sprintf("User %v is unsafe", userid), nil)
    }

    empNodes := queryAll(opBranch, fmt.Sprintf("descendant-or-self::employee[@person='%s']", uid))
    if len(empNodes) == 0 {
        return nil, newInternError("FORBIDDEN-FOR-OP", fmt.Sprintf("User %v is not accountable to operator %v", userid, operatorID), nil)
    }
    return empNodes[0], nil
}

func (dk *configDataKeeper) fireEmployee(userid, operator string) map[string]interface{} {
    if userid == "" {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Not all required parameters are given: user id is %v", userid), nil).dict4api
    }

    if dk._getUserNode(userid) == nil {
        return newInternError("USER-UNKNOWN", fmt.Sprintf("User %v is unknown", userid), nil).dict4api
    }

    branches := dk.userBranches(userid)
    if len(branches) == 0 {
        return newInternError("ALREADY-UNEMPLOYED", fmt.Sprintf("User '%v' already unemployed", userid), nil).dict4api
    }

    empNode, ex := dk._get_empNode_relOp(operator, userid)
    if ex != nil {
        return ex.dict4api
    }

    branch := ""
    if empNode.Parent != nil && empNode.Parent.Parent != nil {
        branch = empNode.Parent.Parent.SelectAttr("id")
    }
    pos := empNode.SelectAttr("pos")
    empNode.RemoveAttr("person")
    dk._save(false)

    return map[string]interface{}{"result": true, "branch": branch, "pos": pos}
}

func (dk *configDataKeeper) _get_brNode_relOp(operatorID, branchID string) (*xmlquery.Node, *internError) {
    opBranch, ex := dk._get_operatorS_branch(operatorID)
    if ex != nil {
        return nil, ex
    }

    safeBranch, err := safeXPathValue(branchID)
    if err != nil {
        return nil, newInternError("WRONG-FORMAT", fmt.Sprintf("Branch %v is unsafe", branchID), nil)
    }

    brNodes := queryAll(opBranch, fmt.Sprintf("descendant-or-self::branch[@id='%s']", safeBranch))
    if len(brNodes) == 0 {
        return nil, newInternError("FORBIDDEN-FOR-OP", fmt.Sprintf("Branch %v is not accountable to operator %v", branchID, operatorID), nil)
    }
    return brNodes[0], nil
}

func (dk *configDataKeeper) hireEmployee(userid, branchID, pos, operator string) map[string]interface{} {
    if userid == "" || branchID == "" || pos == "" {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Not all required parameters are given: user id is %v, branch is %v, pos is %v", userid, branchID, pos), nil).dict4api
    }

    if dk._getUserNode(userid) == nil {
        return newInternError("USER-UNKNOWN", fmt.Sprintf("User %v is unknown", userid), nil).dict4api
    }

    if branches := dk.userBranches(userid); len(branches) != 0 {
        return newInternError("ALREADY-EMPLOYED", fmt.Sprintf("User '%v' already employed at %v", userid, branches), nil).dict4api
    }

    safeBranch, err := safeXPathValue(branchID)
    if err != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Branch %v is unsafe", branchID), nil).dict4api
    }

    safePos, err := safeXPathValue(pos)
    if err != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Position %v is unsafe", pos), nil).dict4api
    }

    branchNodes := queryAll(dk.xmlstorage, fmt.Sprintf("//branch[@id='%s']", safeBranch))
    if len(branchNodes) == 0 {
        return newInternError("BRANCH-UNKNOWN", fmt.Sprintf("Branch '%v' does not exist", branchID), nil).dict4api
    }

    empNodes := queryAll(branchNodes[0], fmt.Sprintf("employees/employee[@pos='%s' and not(@person)]", safePos))
    if len(empNodes) == 0 {
        return newInternError("NO-VACANT-POSITIONS", fmt.Sprintf("No vacant positions for '%v' in '%v'", pos, branchID), nil).dict4api
    }

    if _, ex := dk._get_brNode_relOp(operator, branchID); ex != nil {
        return ex.dict4api
    }

    empNodes[0].SetAttr("person", userid)
    dk._save(false)

    return map[string]interface{}{"result": true}
}

func (dk *configDataKeeper) empSubbranchesList(userid string, allLevels, excludeOwn bool) map[string]interface{} {
    safeID, err := safeXPathValue(userid)
    if err != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("User %v is unsafe", userid), nil).dict4api
    }

    if dk._getUserNode(safeID) == nil {
        return map[string]interface{}{"result": false, "reason": "USER-UNKNOWN"}
    }

    branchesNodeSet := map[string]struct{}{}
    for _, branch := range queryAll(dk.xmlstorage, fmt.Sprintf("//branch[employees/employee[@person='%s']]", safeID)) {
        if !excludeOwn {
            if id := branch.SelectAttr("id"); id != "" {
                branchesNodeSet[id] = struct{}{}
            }
        }

        if allLevels {
            for _, sub := range queryAll(branch, "descendant::branch") {
                if id := sub.SelectAttr("id"); id != "" {
                    branchesNodeSet[id] = struct{}{}
                }
            }
        } else {
            for _, sub := range queryAll(branch, "branches/branch") {
                if id := sub.SelectAttr("id"); id != "" {
                    branchesNodeSet[id] = struct{}{}
                }
            }
        }
    }

    return map[string]interface{}{"result": true, "subbranches": sortedSet(branchesNodeSet)}
}

func (dk *configDataKeeper) empFuncsetsList(userid string) map[string]interface{} {
    if dk._getUserNode(userid) == nil {
        return map[string]interface{}{"result": false, "reason": "USER-UNKNOWN"}
    }

    return map[string]interface{}{"result": true, "funcsets": dk._userFuncSets(userid)}
}

func (dk *configDataKeeper) __empFunctionIds(userid string) []string {
    funcsAllowed := map[string]struct{}{}
    for _, fsID := range dk._userFuncSets(userid) {
        // Query universe.xml (dk.xmlstorage) for functions in funcset
        for _, fnode := range queryAll(dk.xmlstorage, fmt.Sprintf("//funcset[@id='%s']/func/@id", fsID)) {
            if fnode.Type == xmlquery.AttributeNode {
                funcsAllowed[strings.TrimSpace(fnode.InnerText())] = struct{}{}
            }
        }
    }

    // Get all known functions from catalogues.xml
    known := map[string]struct{}{}
    for _, row := range queryAll(dk.xmlcats, "/catalogues/functions_catalogue/function") {
        if id := row.SelectAttr("id"); id != "" {
            known[id] = struct{}{}
        }
    }

    // Return intersection
    funcs := make([]string, 0)
    for f := range intersectMaps(funcsAllowed, known) {
        funcs = append(funcs, f)
    }
    return funcs
}

func (dk *configDataKeeper) empFunctionsList(userid, prop string) map[string]interface{} {
    if dk._getUserNode(userid) == nil {
        return map[string]interface{}{"result": false, "reason": "USER-UNKNOWN"}
    }

    if prop == "" {
        prop = "id"
    }

    funcsSet := map[string]struct{}{}
    for _, fid := range dk.__empFunctionIds(userid) {
        tmp := dk.reviewFunctions(prop, fid)
        if tmp != nil && tmp["result"].(bool) {
            if props, ok := tmp["props"].(map[string]interface{}); ok {
                if val, ok2 := props[prop]; ok2 {
                    if str, ok3 := val.(string); ok3 {
                        funcsSet[str] = struct{}{}
                    }
                }
            }
        }
    }

    return map[string]interface{}{
        "result":    true,
        "prop":      prop,
        "functions": sortedSet(funcsSet),
    }
}

func (dk *configDataKeeper) empFunctionsReview(userid, props string) map[string]interface{} {
    if dk._getUserNode(userid) == nil {
        return map[string]interface{}{"result": false, "reason": "USER-UNKNOWN"}
    }

    funcs := make([]interface{}, 0)
    for _, fid := range dk.__empFunctionIds(userid) {
        tmp := dk.reviewFunctions(props, fid)
        if tmp != nil && tmp["result"].(bool) {
            if p, ok := tmp["props"].(map[string]interface{}); ok {
                funcs = append(funcs, p)
            }
        }
    }
    return map[string]interface{}{"result": true, "props": props, "functions": funcs}
}

func (dk *configDataKeeper) branchEmployeesList(branchID string, includeSubBranches bool) map[string]interface{} {
    safeBranch, err := safeXPathValue(branchID)
    if err != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Branch %v is unsafe", branchID), nil).dict4api
    }

    br := queryOne(dk.xmlstorage, fmt.Sprintf("//branch[@id='%s']", safeBranch))
    if br == nil {
        return newInternError("BRANCH-UNKNOWN", fmt.Sprintf("Branch '%v' is unknown", branchID), nil).dict4api
    }

    expr := "employees/employee/@person"
    if includeSubBranches {
        expr = "descendant::employees/employee/@person"
    }

    names := make([]interface{}, 0)
    for _, emp := range queryAll(br, expr) {
        if emp.Type == xmlquery.AttributeNode {
            v := strings.TrimSpace(emp.InnerText())
            if v != "" {
                names = append(names, v)
            }
            continue
        }
        if v := emp.SelectAttr("person"); v != "" {
            names = append(names, v)
        }
    }

    return map[string]interface{}{"result": true, "employees": names}
}

var _fpHow = map[string]struct {
    path      string
    transform func(string) string
}{
    "id":          {"@id", func(x string) string { return x }},
    "name":        {"@name", func(x string) string { return x }},
    "title":       {"@title", func(x string) string { return x }},
    "description": {"@descr", func(x string) string { return x }},
    "callpath":    {"call/url/text()", func(x string) string { return strings.SplitN(x, "?", 2)[0] }},
    "method":      {"call/@method", func(x string) string { return x }},
    "contenttype": {"call/body/@content-type", func(x string) string { return x }},
}

func (dk *configDataKeeper) listFunctions(prop string) map[string]interface{} {
    cfg, ok := _fpHow[prop]
    if !ok {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Unknown function property %v", prop), nil).dict4api
    }

    values := make([]string, 0)
    for _, fn := range queryAll(dk.xmlcats, "/catalogues/functions_catalogue/function") {
        raw := extractValue(fn, cfg.path)
        if raw == "" {
            continue
        }
        values = append(values, cfg.transform(raw))
    }

    return map[string]interface{}{
        "result":   true,
        "property": prop,
        "values":   uniqueStrings(values),
    }
}

func (dk *configDataKeeper) reviewFunctions(props string, functionID string) map[string]interface{} {
    propl := splitCSV(props)
    if len(propl) == 0 {
        return newInternError("WRONG-FORMAT", "No properties specified", nil).dict4api
    }

    for _, p := range propl {
        if _, ok := _fpHow[p]; !ok {
            return newInternError("WRONG-FORMAT", fmt.Sprintf("One or more properties in %v are unknown", propl), nil).dict4api
        }
    }

    funcNodes := queryAll(dk.xmlcats, "/catalogues/functions_catalogue/function")
    if functionID != "" {
        safeID, err := safeXPathValue(functionID)
        if err != nil {
            return newInternError("WRONG-FORMAT", fmt.Sprintf("Function id %v is unsafe", functionID), nil).dict4api
        }
        funcNodes = queryAll(dk.xmlcats, fmt.Sprintf("/catalogues/functions_catalogue/function[@id='%s']", safeID))
        if len(funcNodes) == 0 {
            return newInternError("FUNCTION-UNKNOWN", fmt.Sprintf("Function %v is not described in catalogue", functionID), nil).dict4api
        }
    }

    if functionID == "" {
        result := make([]interface{}, 0)
        for _, fn := range funcNodes {
            entry := map[string]interface{}{}
            for _, p := range propl {
                if val := _fpHow[p].transform(extractValue(fn, _fpHow[p].path)); val != "" {
                    entry[p] = val
                }
            }
            result = append(result, entry)
        }
        return map[string]interface{}{"result": true, "functions": result}
    }

    fn := funcNodes[0]
    entry := map[string]interface{}{}
    for _, p := range propl {
        if val := _fpHow[p].transform(extractValue(fn, _fpHow[p].path)); val != "" {
            entry[p] = val
        }
    }

    return map[string]interface{}{
        "result":     true,
        "props":      entry,
        "function_id": fn.SelectAttr("id"),
    }
}

func (dk *configDataKeeper) getFunctionDef(funcID, pureXML string, header string) map[string]interface{} {
    safeID, err := safeXPathValue(funcID)
    if err != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Function %v is unsafe", funcID), nil).dict4api
    }

    fnNodes := queryAll(dk.xmlcats, fmt.Sprintf("/catalogues/functions_catalogue/function[@id='%s']", safeID))
    if len(fnNodes) == 0 {
        return newInternError("FUNCTION-UNKNOWN", fmt.Sprintf("Function '%v' is unknown", funcID), nil).dict4api
    }

    definition := header + fnNodes[0].OutputXML(true)
    _ = pureXML
    return map[string]interface{}{"result": true, "definition": definition}
}

func (dk *configDataKeeper) postFunctionDef(funcDescrText string) map[string]interface{} {
    parsed, err := xmlquery.Parse(strings.NewReader(funcDescrText))
    if err != nil {
        return map[string]interface{}{"result": false, "reason": "WRONG-DATA", "details": repr(err)}
    }

    fnNode := firstElement(parsed)
    if fnNode == nil {
        return map[string]interface{}{"result": false, "reason": "WRONG-DATA", "details": "Empty XML payload"}
    }

    funcID := fnNode.SelectAttr("id")
    if funcID == "" {
        return map[string]interface{}{"result": false, "reason": "WRONG-DATA", "details": "Function does not have \"id\" attribute"}
    }

    safeID, err := safeXPathValue(funcID)
    if err != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Function %v is unsafe", funcID), nil).dict4api
    }
    fnNode.SetAttr("id", safeID)

    funcsCat := queryOne(dk.xmlcats, "/catalogues/functions_catalogue")
    if funcsCat == nil {
        return newInternError("DATABASE-ERROR", "Functions catalogue is missing", nil).dict4api
    }

    existing := queryAll(funcsCat, fmt.Sprintf("function[@id='%s']", safeID))
    if len(existing) == 0 {
        xmlquery.AddChild(funcsCat, fnNode)
        dk._save(true)
        return map[string]interface{}{"result": true, "function_id": safeID, "status": "APPENDED"}
    }

    oldNode := existing[0]
    oldTxt := oldNode.OutputXML(true)
    oldNode.RemoveFromTree()
    xmlquery.AddChild(funcsCat, fnNode)
    dk._save(true)
    return map[string]interface{}{"result": true, "function_id": safeID, "status": "REPLACED", "old_definition": oldTxt}
}

func repr(err error) string {
    if err == nil {
        return ""
    }
    return fmt.Sprintf("%#v", err)
}

func (dk *configDataKeeper) deleteFunctionDef(funcID string) map[string]interface{} {
    if funcID == "" {
        return map[string]interface{}{"result": false, "reason": "WRONG-FORMAT"}
    }

    safeID, err := safeXPathValue(funcID)
    if err != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Function %v is unsafe", funcID), nil).dict4api
    }

    funcsCat := queryOne(dk.xmlcats, "/catalogues/functions_catalogue")
    if funcsCat == nil {
        return newInternError("DATABASE-ERROR", "Functions catalogue is missing", nil).dict4api
    }

    nodes := queryAll(funcsCat, fmt.Sprintf("function[@id='%s']", safeID))
    if len(nodes) == 0 {
        return newInternError("FUNCTION-UNKNOWN", fmt.Sprintf("Function '%v' is unknown", safeID), nil).dict4api
    }

    oldTxt := nodes[0].OutputXML(true)
    nodes[0].RemoveFromTree()
    dk._save(true)
    return map[string]interface{}{"result": true, "function_id": safeID, "status": "DELETED", "old_definition": oldTxt}
}

func (dk *configDataKeeper) modifyFuncTagset(funcID, method string, tagset []string, readOnly bool) map[string]interface{} {
    if funcID == "" || method == "" {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Required parameter not given: funcId %v, method %v", funcID, method), nil).dict4api
    }

    safeID, err := safeXPathValue(funcID)
    if err != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Function %v is unsafe", funcID), nil).dict4api
    }

    funcNodes := queryAll(dk.xmlcats, fmt.Sprintf("/catalogues/functions_catalogue/function[@id='%s']", safeID))
    if len(funcNodes) == 0 {
        return newInternError("FUNCTION-UNKNOWN", fmt.Sprintf("Function %v is unknown", safeID), nil).dict4api
    }

    oldTagSet := map[string]struct{}{}
    for _, t := range strings.Split(funcNodes[0].SelectAttr("tags"), ",") {
        t = strings.TrimSpace(t)
        if t != "" {
            oldTagSet[t] = struct{}{}
        }
    }

    requested := map[string]struct{}{}
    for _, t := range tagset {
        t = strings.TrimSpace(t)
        if t != "" {
            requested[t] = struct{}{}
        }
    }

    nextSet := map[string]struct{}{}
    switch method {
    case "SET":
        if !readOnly {
            nextSet = requested
        }
    case "OR":
        nextSet = mergeSets(oldTagSet, requested)
    case "AND":
        nextSet = intersectMaps(oldTagSet, requested)
    case "MINUS":
        nextSet = map[string]struct{}{}
        for k := range oldTagSet {
            if _, ok := requested[k]; !ok {
                nextSet[k] = struct{}{}
            }
        }
    default:
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Method %v is unapplicable", method), map[string]interface{}{"wrong_value": method}).dict4api
    }

    retTs := strings.Join(sortedSet(nextSet), ",")
    if !readOnly {
        funcNodes[0].SetAttr("tags", retTs)
        dk._save(true)
    }

    return map[string]interface{}{"result": true, "tagset": retTs}
}

func (dk *configDataKeeper) getAgents() []string {
    return dk.agentsKeeper.getAllAgentIds()
}

func (dk *configDataKeeper) getSubBranchesOfAgent(agentID string) []string {
    branchID, ok := dk.agentsKeeper.getBranchName(agentID)
    if !ok {
        return []string{}
    }

    safeBranch, err := safeXPathValue(branchID)
    if err != nil {
        return []string{}
    }

    ret := make([]string, 0)
    for _, b := range queryAll(dk.xmlstorage, fmt.Sprintf("//branch[@id='%s']/descendant-or-self::branch/@id", safeBranch)) {
        if b.Type == xmlquery.AttributeNode {
            ret = append(ret, strings.TrimSpace(b.InnerText()))
            continue
        }
        if id := b.SelectAttr("id"); id != "" {
            ret = append(ret, id)
        }
    }

    return uniqueStrings(ret)
}

func (dk *configDataKeeper) registerAgentInBranch(branchID, agentID string, move bool, descr, location, tags, extraxml string) map[string]interface{} {
    if branchID == "" || agentID == "" {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Required argument not given: branch is %v, agent is %v", branchID, agentID), nil).dict4api
    }

    if branchID == "*ROOT*" {
        rootBranch := queryOne(dk.xmlstorage, "/universe/branches/branch[1]")
        if rootBranch == nil {
            return newInternError("DATABASE-ERROR", "Root branch is not defined", nil).dict4api
        }
        branchID = rootBranch.SelectAttr("id")
    }

    safeBranch, err := safeXPathValue(branchID)
    if err != nil {
        return newInternError("WRONG-FORMAT", fmt.Sprintf("Branch %v is unsafe", branchID), nil).dict4api
    }

    current := dk.agentsKeeper.getAgentDict(agentID, false)

    if !move {
        if current != nil {
            return newInternError("ALREADY-EXISTS", fmt.Sprintf("Agent %v already registered in branch %v", agentID, current["branch"]), map[string]interface{}{"bad_value": agentID}).dict4api
        }

        if _, err := xmlquery.Parse(strings.NewReader("<extra>" + extraxml + "</extra>")); err != nil {
            return newInternError("WRONG-FORMAT", fmt.Sprintf("extraxml field does not fit into XML format, details: %v", err), nil).dict4api
        }
    } else {
        if current == nil {
            return newInternError("AGENT-UNKNOWN", fmt.Sprintf("Agent %v is never registered", agentID), map[string]interface{}{"bad_value": agentID}).dict4api
        }
        currBranchName := fmt.Sprintf("%v", current["branch"])
        safeCurrBranch, err := safeXPathValue(currBranchName)
        if err != nil {
            return newInternError("DATABASE-ERROR", fmt.Sprintf("Branch for agent %v is unsafe", currBranchName), nil).dict4api
        }

        currBranchNode := queryOne(dk.xmlstorage, fmt.Sprintf("//branch[@id='%s']", safeCurrBranch))
        if currBranchNode == nil {
            return newInternError("DATABASE-ERROR", fmt.Sprintf("Branch %v referenced from agent %v does not longer exist", currBranchName, agentID), nil).dict4api
        }

        if len(queryAll(currBranchNode, fmt.Sprintf("descendant-or-self::branch[@id='%s']", safeBranch))) == 0 {
            return newInternError("NOT-IN-SET", fmt.Sprintf("Branch %v is not a subsidiary of a branch %v containing agent %v", branchID, currBranchName, agentID), map[string]interface{}{"bad_value": branchID}).dict4api
        }

        dk.unregisterAgent(agentID)
    }

    tagsTrim := []string{}
    for _, t := range strings.Split(tags, ",") {
        t = strings.TrimSpace(t)
        if t != "" {
            tagsTrim = append(tagsTrim, t)
        }
    }

    if err := dk.agentsKeeper.addAgent(agentID, safeBranch, descr, location, extraxml, tagsTrim); err != nil {
        return newInternError("DATABASE-ERROR", err.Error(), nil).dict4api
    }

    return map[string]interface{}{"result": true}
}

func (dk *configDataKeeper) unregisterAgent(agentID string) map[string]interface{} {
    if err := dk.agentsKeeper.deleteAgent(agentID); err != nil {
        return newInternError("AGENT-UNKNOWN", fmt.Sprintf("Agent %v is never registered", agentID), map[string]interface{}{"bad_value": agentID}).dict4api
    }
    return map[string]interface{}{"result": true}
}

func (dk *configDataKeeper) agentDetailsXml(agentID string) map[string]interface{} {
    agdict := dk.agentsKeeper.getAgentDict(agentID, true)
    if agdict == nil {
        return newInternError("AGENT-UNKNOWN", fmt.Sprintf("Agent %v is never registered", agentID), map[string]interface{}{"bad_value": agentID}).dict4api
    }

    tags := agdict["tags"].([]string)
    sort.Strings(tags)

    type aginfo struct {
        XMLName  xml.Name `xml:"aginfo"`
        Descr    string   `xml:"descr"`
        Location string   `xml:"location"`
        Extra    string   `xml:"extra"`
        Tags     []string `xml:"tag"`
    }

    payload := aginfo{
        Descr:    fmt.Sprintf("%v", agdict["descr"]),
        Location: fmt.Sprintf("%v", agdict["location"]),
        Extra:    fmt.Sprintf("%v", agdict["extra"]),
        Tags:     tags,
    }

    b, err := xml.MarshalIndent(payload, "", "  ")
    if err != nil {
        return newInternError("DATABASE-ERROR", err.Error(), nil).dict4api
    }

    return map[string]interface{}{
        "result":  true,
        "details": string(b),
    }
}

func (dk *configDataKeeper) agentDetailsJson(agentID string) map[string]interface{} {
    agdict := dk.agentsKeeper.getAgentDict(agentID, true)
    if agdict == nil {
        return newInternError("AGENT-UNKNOWN", fmt.Sprintf("Agent %v is never registered", agentID), map[string]interface{}{"bad_value": agentID}).dict4api
    }

    tags := agdict["tags"].([]string)
    sort.Strings(tags)

    return map[string]interface{}{
        "result": true,
        "details": map[string]interface{}{
            "descr":    agdict["descr"],
            "location": agdict["location"],
            "tags":     strings.Join(tags, ","),
            "extra":    agdict["extra"],
        },
    }
}

func (dk *configDataKeeper) listAgents(branchID string, withSubs bool, withLoc bool) map[string]interface{} {
    if branchID != "*ALL*" {
        safeBranch, err := safeXPathValue(branchID)
        if err != nil {
            return newInternError("WRONG-FORMAT", fmt.Sprintf("Branch %v is unsafe", branchID), nil).dict4api
        }
        branchID = safeBranch
    }

    var branches []string
    if branchID == "*ALL*" {
        for _, b := range queryAll(dk.xmlstorage, "/universe/branches/branch") {
            if id := b.SelectAttr("id"); id != "" {
                branches = append(branches, id)
            }
        }
    } else {
        for _, b := range queryAll(dk.xmlstorage, fmt.Sprintf("//branch[@id='%s']/descendant-or-self::branch/@id", branchID)) {
            if b.Type == xmlquery.AttributeNode {
                branches = append(branches, strings.TrimSpace(b.InnerText()))
                continue
            }
            if id := b.SelectAttr("id"); id != "" {
                branches = append(branches, id)
            }
        }
    }

    if len(branches) == 0 {
        return map[string]interface{}{"result": true, "report": []interface{}{}}
    }

    agents := dk.agentsKeeper.getAgentsByBranches(branches)
    if withLoc {
        rep := make([]interface{}, 0, len(agents))
        for _, ag := range agents {
            rep = append(rep, map[string]interface{}{"agent": ag[0], "branch": ag[1]})
        }
        return map[string]interface{}{"result": true, "report": rep}
    }

    rep := make([]interface{}, 0, len(agents))
    for _, ag := range agents {
        rep = append(rep, ag[0])
    }

    return map[string]interface{}{"result": true, "report": rep}
}
