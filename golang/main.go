package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

type runLocationConfig struct {
	Port          int      `yaml:"port"`
	CorsWhitelist []string `yaml:"cors_whitelist"`
}

type appConfig struct {
	DefaultRunLocation string                       `yaml:"default_run_location"`
	SessionMaxDefault  int64                        `yaml:"session_max_default"`
	RunLocations       map[string]runLocationConfig `yaml:"run_locations"`
}

var (
	storage       *configDataKeeper
	corsWhitelist map[string]struct{}
)

func firstExisting(paths ...string) (string, error) {
	for _, p := range paths {
		if _, err := os.Stat(p); err == nil {
			return p, nil
		}
	}
	return "", fmt.Errorf("no existing path from candidates: %v", paths)
}

func stripBOM(data []byte) []byte {
	if len(data) >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
		return data[3:]
	}
	return data
}

func loadAppConfig(path string) (*appConfig, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var cfg appConfig
	if err := yaml.Unmarshal(stripBOM(raw), &cfg); err != nil {
		return nil, err
	}

	if cfg.DefaultRunLocation == "" {
		return nil, fmt.Errorf("missing default_run_location in config")
	}

	return &cfg, nil
}

func parseRunAt(argv []string, defaultRunAt string) string {
	for _, arg := range argv {
		if strings.HasPrefix(arg, "-runat=") {
			return strings.TrimPrefix(arg, "-runat=")
		}
		if strings.HasPrefix(arg, "--runat=") {
			return strings.TrimPrefix(arg, "--runat=")
		}
	}
	return defaultRunAt
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if origin := r.Header.Get("Origin"); origin != "" {
			if corsWhitelist != nil {
				if _, ok := corsWhitelist[origin]; ok {
					w.Header().Set("Access-Control-Allow-Origin", origin)
				}
			}
		}
		next.ServeHTTP(w, r)
	})
}

func ensureMethods(w http.ResponseWriter, method string, allowed ...string) bool {
	for _, m := range allowed {
		if method == m {
			return true
		}
	}
	writeJSON(w, map[string]interface{}{
		"result": false,
		"reason": "NOT-ALLOWED",
	})
	return false
}

func writeXML(w http.ResponseWriter, payload string, code int) {
	w.Header().Set("Content-Type", "text/xml; charset=utf-8")
	w.WriteHeader(code)
	_, _ = w.Write([]byte(payload))
}

func badFormat(msg string) map[string]interface{} {
	return map[string]interface{}{
		"result":  false,
		"reason":  "WRONG-FORMAT",
		"warning": msg,
	}
}

func handleRouteRoot(w http.ResponseWriter, r *http.Request) {
	http.Redirect(w, r, "/aac/static/techIndex.html", http.StatusFound)
}

func handleAacRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/aac/" || r.URL.Path == "/aac" {
		http.Redirect(w, r, "/aac/static/techIndex.html", http.StatusFound)
		return
	}
	http.NotFound(w, r)
}

func parseRequestForm(r *http.Request) {
	_ = r.ParseForm()
}

func asStringSlice(value interface{}) []string {
	switch v := value.(type) {
	case []string:
		return v
	case []interface{}:
		out := make([]string, 0, len(v))
		for _, item := range v {
			if item == nil {
				continue
			}
			if s, ok := item.(string); ok {
				out = append(out, s)
				continue
			}
			out = append(out, fmt.Sprintf("%v", item))
		}
		return out
	default:
		return []string{}
	}
}

func storageUsers() []string {
	return asStringSlice(storage.listUsers()["users"])
}

func storageBranches() []string {
	return storage.listBranches()
}

func storageFuncsets() []string {
	return storage.getFuncsets()
}

func storageFunctionIDs() []string {
	return asStringSlice(storage.listFunctions("id")["values"])
}

func handleAuthorize(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)

	username := strings.TrimSpace(r.FormValue("username"))
	secret := strings.TrimSpace(r.FormValue("secret"))
	appName := ""
	if r.URL.Path == "/aac/authorize" {
		appName = r.FormValue("app")
	}

	if username == "" || secret == "" {
		writeJSON(w, map[string]interface{}{
			"result":   true,
			"userList": storageUsers(),
		})
		return
	}

	writeJSON(w, storage.authorize(username, secret, appName))
}

func handleUserCreate(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)

	username := strings.TrimSpace(r.FormValue("username"))
	secret := strings.TrimSpace(r.FormValue("secret"))
	operator := strings.TrimSpace(r.FormValue("operator"))
	pswLifeTime := r.FormValue("pswlifetime")
	readableName := r.FormValue("readablename")
	sessionMax := r.FormValue("sessionmax")

	if r.Method == http.MethodGet {
		writeJSON(w, map[string]interface{}{
			"result":   true,
			"users":    storageUsers(),
			"operList": storageUsers(),
			"init": map[string]interface{}{
				"sessionMax": storage.dfltSessMax,
			},
		})
		return
	}

	writeJSON(w, storage.createUser(username, secret, operator, pswLifeTime, readableName, sessionMax))
}

func handleUserChange(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)

	username := strings.TrimSpace(r.FormValue("username"))
	secret := strings.TrimSpace(r.FormValue("secret"))
	operator := strings.TrimSpace(r.FormValue("operator"))
	pswLifeTime := r.FormValue("pswlifetime")
	readableName := r.FormValue("readablename")
	sessionMax := r.FormValue("sessionmax")
	if r.Method == http.MethodGet || secret == "" {
		oldData := map[string]interface{}{}
		if username != "" {
			details := storage.get_user_reg_details(username, "")
			if ok, _ := details["result"].(bool); ok {
				oldData = details
			}
		}

		writeJSON(w, map[string]interface{}{
			"result":         true,
			"users":          storageUsers(),
			"operList":       storageUsers(),
			"init":           oldData,
			"userAutoSubmit": secret == "",
			"useridInit":     username,
		})
		return
	}

	writeJSON(w, storage.changeUser(username, secret, operator, pswLifeTime, readableName, sessionMax))
}

func handleUserDetails(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	username := strings.TrimSpace(r.FormValue("username"))
	appName := r.FormValue("app")
	if username == "" {
		writeJSON(w, map[string]interface{}{
			"result":   true,
			"userList": storageUsers(),
		})
		return
	}
	writeJSON(w, storage.get_user_reg_details(username, appName))
}

func handleUsersList(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	writeJSON(w, storage.listUsers())
}

func handleFunctionsList(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	prop := strings.TrimSpace(r.FormValue("prop"))
	if prop == "" {
		writeJSON(w, map[string]interface{}{"result": true})
		return
	}
	writeJSON(w, storage.listFunctions(prop))
}

func handleFunctionReview(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	props := strings.TrimSpace(r.FormValue("props"))
	functionID := strings.TrimSpace(r.FormValue("funcId"))
	if r.URL.Path == "/aac/functions/review" {
		writeJSON(w, map[string]interface{}{"result": true})
		return
	}
	if props == "" || functionID == "" {
		writeJSON(w, map[string]interface{}{
			"result":   true,
			"funcList": storageFunctionIDs(),
		})
		return
	}
	writeJSON(w, storage.reviewFunctions(props, functionID))
}

func handleUserDelete(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	if r.Method == http.MethodGet {
		writeJSON(w, map[string]interface{}{
			"result":         true,
			"userList":       storageUsers(),
			"operList":       storageUsers(),
			"operatorDriven": true,
			"formMethod":     "post",
		})
		return
	}
	parseRequestForm(r)
	username := strings.TrimSpace(r.FormValue("username"))
	operator := strings.TrimSpace(r.FormValue("operator"))
	writeJSON(w, storage.deleteUser(username, operator))
}

func handleEmployeeFire(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	if r.Method == http.MethodGet {
		writeJSON(w, map[string]interface{}{
			"result":         true,
			"userList":       storageUsers(),
			"operList":       storageUsers(),
			"operatorDriven": true,
			"formMethod":     "post",
		})
		return
	}
	parseRequestForm(r)
	username := strings.TrimSpace(r.FormValue("username"))
	operator := strings.TrimSpace(r.FormValue("operator"))
	writeJSON(w, storage.fireEmployee(username, operator))
}

func handleEmployeeHire(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)
	username := strings.TrimSpace(r.FormValue("username"))
	branch := strings.TrimSpace(r.FormValue("branch"))
	position := strings.TrimSpace(r.FormValue("position"))
	operator := strings.TrimSpace(r.FormValue("operator"))
	if r.Method == http.MethodGet || branch == "" || position == "" {
		writeJSON(w, map[string]interface{}{
			"result":       true,
			"userList":     storageUsers(),
			"branchReview": storage.reviewBranches(position),
			"posReview":    storage.reviewPositions(branch),
			"init": map[string]interface{}{
				"u": username,
				"b": branch,
				"p": position,
			},
			"operList": storageUsers(),
		})
		return
	}
	writeJSON(w, storage.hireEmployee(username, branch, position, operator))
}

func handleCreateBranchPosition(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)
	branch := strings.TrimSpace(r.FormValue("branch"))
	role := strings.TrimSpace(r.FormValue("role"))
	if r.Method == http.MethodGet || branch == "" || role == "" {
		writeJSON(w, map[string]interface{}{
			"result":           true,
			"formMethod":       "post",
			"branchList":       storageBranches(),
			"branchInit":       branch,
			"branchAutoSubmit": role == "",
			"rolesList":        storage.listEnabledRoles4Branch(branch),
			"roleRequired":     branch != "",
		})
		return
	}
	writeJSON(w, storage.createBranchPosition(branch, role))
}

func handleDeleteBranchPosition(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)
	branch := strings.TrimSpace(r.FormValue("branch"))
	role := strings.TrimSpace(r.FormValue("role"))
	if r.Method == http.MethodGet || branch == "" || role == "" {
		writeJSON(w, map[string]interface{}{
			"result":           true,
			"formMethod":       "post",
			"branchList":       storageBranches(),
			"branchInit":       branch,
			"branchAutoSubmit": role == "",
			"rolesList":        storage.getBranchVacantPositions(branch),
			"roleRequired":     branch != "",
		})
		return
	}
	writeJSON(w, storage.deleteBranchPosition(branch, role))
}

func handleEmpSubBranches(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	username := strings.TrimSpace(r.FormValue("username"))
	if username == "" {
		writeJSON(w, map[string]interface{}{
			"result":   true,
			"userList": storageUsers(),
		})
		return
	}
	allLevels := boolFromParam(r.FormValue("allLevels"), true)
	excludeOwn := boolFromParam(r.FormValue("excludeOwn"), false)
	writeJSON(w, storage.empSubbranchesList(username, allLevels, excludeOwn))
}

func handleEmpFuncsets(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	username := strings.TrimSpace(r.FormValue("username"))
	if username == "" {
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"userList":   storageUsers(),
			"formMethod": "get",
		})
		return
	}
	writeJSON(w, storage.empFuncsetsList(username))
}

func handleEmpFunctionsList(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	username := strings.TrimSpace(r.FormValue("username"))
	prop := r.FormValue("prop")
	if prop == "" {
		prop = "id"
	}
	if username == "" {
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"userList":   storageUsers(),
			"formMethod": "get",
		})
		return
	}
	writeJSON(w, storage.empFunctionsList(username, prop))
}

func handleEmpFunctionsReview(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	username := strings.TrimSpace(r.FormValue("username"))
	props := strings.TrimSpace(r.FormValue("props"))
	if username == "" || props == "" {
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"userList":   storageUsers(),
			"formMethod": "get",
		})
		return
	}
	writeJSON(w, storage.empFunctionsReview(username, props))
}

func handleBranchEmployeesList(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	branchID := r.FormValue("branch")
	includeSubBranches := boolFromParam(r.FormValue("includeSubBranches"), false)
	if branchID == "" {
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"branchList": storageBranches(),
			"cboxes": [][2]string{
				{"includeSubBranches", "Include sub-branches"},
			},
		})
		return
	}
	writeJSON(w, storage.branchEmployeesList(branchID, includeSubBranches))
}

func handleHrPositions(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	branchID := r.FormValue("branch")
	perRole := boolFromParam(r.FormValue("perRole"), false)
	onlyVacant := boolFromParam(r.FormValue("onlyVacant"), false)
	if branchID == "" {
		allBranches := make([]string, 0, len(storageBranches())+1)
		allBranches = append(allBranches, "*ALL*")
		allBranches = append(allBranches, storageBranches()...)
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"branchList": allBranches,
			"cboxes": [][3]interface{}{
				{"perRole", "Per-role report", true},
				{"onlyVacant", "Report only vacant positions", true},
			},
		})
		return
	}
	writeJSON(w, storage.get_branches_with_positions(branchID, perRole, onlyVacant))
}

func handleFunctionInfo(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	functionID := r.FormValue("funcId")
	pure := boolFromParam(r.FormValue("pure"), false)
	xsltref := strings.TrimSpace(r.FormValue("xsltref"))
	if functionID == "" {
		writeJSON(w, map[string]interface{}{
			"result":       true,
			"funcRequired": true,
			"funcList":     storageFunctionIDs(),
		})
		return
	}

	header := ""
	if xsltref != "" {
		header = fmt.Sprintf("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<?xml-stylesheet type=\"text/xsl\" href=%q?>\n\n", xsltref)
	}

	def := storage.getFunctionDef(functionID, "yes", header)
	if pure {
		if result, ok := def["result"].(bool); ok && result {
			writeXML(w, fmt.Sprintf("%v", def["definition"]), http.StatusOK)
			return
		}
	}

	writeJSON(w, def)
}

func handleFunctionDelete(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	if r.Method == http.MethodGet {
		writeJSON(w, map[string]interface{}{
			"result":       true,
			"funcRequired": true,
			"funcList":     storageFunctionIDs(),
			"formMethod":   "post",
		})
		return
	}
	parseRequestForm(r)
	functionID := strings.TrimSpace(r.FormValue("funcId"))
	writeJSON(w, storage.deleteFunctionDef(functionID))
}

func handleFunctionUploadXmlDescr(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	if r.Method == http.MethodGet {
		writeJSON(w, map[string]interface{}{
			"result": true,
		})
		return
	}
	parseRequestForm(r)
	text := strings.TrimSpace(r.FormValue("xmltext"))
	writeJSON(w, storage.postFunctionDef(text))
}

func handleFunctionUploadXmlFile(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	if r.Method == http.MethodGet {
		writeJSON(w, map[string]interface{}{"result": true})
		return
	}
	if err := r.ParseMultipartForm(10 << 20); err != nil {
		writeJSON(w, badFormat("cannot parse multipart form"))
		return
	}
	file, _, err := r.FormFile("xmlfile")
	if err != nil {
		writeJSON(w, map[string]interface{}{
			"result": false,
			"reason": "WRONG-FORMAT",
		})
		return
	}
	defer file.Close()
	data, err := io.ReadAll(file)
	if err != nil {
		writeJSON(w, badFormat("cannot read uploaded file"))
		return
	}
	writeJSON(w, storage.postFunctionDef(string(data)))
}

func handleFuncsets(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	writeJSON(w, map[string]interface{}{
		"result":   true,
		"funcsets": storage.getFuncsets(),
	})
}

func handleFuncsetCreate(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	if r.Method == http.MethodGet {
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"formMethod": "post",
			"branchList": storageBranches(),
		})
		return
	}
	parseRequestForm(r)
	branch := strings.TrimSpace(r.FormValue("branch"))
	funcset := strings.TrimSpace(r.FormValue("funcset"))
	readableName := r.FormValue("readablename")
	writeJSON(w, storage.funcsetCreate(branch, funcset, readableName))
}

func handleFuncsetDelete(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	if r.Method == http.MethodGet {
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"funcSets":   storageFuncsets(),
			"formMethod": "post",
		})
		return
	}
	parseRequestForm(r)
	funcset := strings.TrimSpace(r.FormValue("funcset"))
	writeJSON(w, storage.funcsetDelete(funcset))
}

func handleFuncsetDetails(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	funcset := strings.TrimSpace(r.FormValue("funcset"))
	if funcset == "" {
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"funcSets":   storageFuncsets(),
			"formMethod": "get",
		})
		return
	}
	writeJSON(w, storage.getFuncsetDetails(funcset))
}

func handleFuncsetFunctionAdd(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	if r.Method == http.MethodGet {
		writeJSON(w, map[string]interface{}{
			"result":       true,
			"funcSets":     storageFuncsets(),
			"funcList":     storageFunctionIDs(),
			"funcRequired": true,
		})
		return
	}
	parseRequestForm(r)
	funcset := strings.TrimSpace(r.FormValue("funcset"))
	functionID := strings.TrimSpace(r.FormValue("funcId"))
	writeJSON(w, storage.funcsetFuncAdd(funcset, functionID))
}

func handleFuncsetFunctionRemove(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)
	funcset := strings.TrimSpace(r.FormValue("funcset"))
	functionID := strings.TrimSpace(r.FormValue("funcId"))
	if r.Method == http.MethodGet || funcset == "" || functionID == "" {
		funcs := []string{}
		if funcset != "" {
			details := storage.getFuncsetDetails(funcset)
			if f, ok := details["functions"].([]string); ok {
				funcs = f
			}
		}
		writeJSON(w, map[string]interface{}{
			"result":            true,
			"funcSets":          storageFuncsets(),
			"funcSetInit":       funcset,
			"funcList":          funcs,
			"funcsetAutoSubmit": funcset == "",
			"funcRequired":      funcset != "",
		})
		return
	}
	writeJSON(w, storage.funcsetFuncRemove(funcset, functionID))
}

func handleRoleFuncsets(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	branch := strings.TrimSpace(r.FormValue("branch"))
	role := strings.TrimSpace(r.FormValue("role"))
	if branch == "" || role == "" {
		writeJSON(w, map[string]interface{}{
			"result":           true,
			"formMethod":       "get",
			"branchList":       storageBranches(),
			"branchInit":       branch,
			"branchAutoSubmit": role == "",
			"rolesList":        storage.listRoles4Branch(branch),
			"roleRequired":     branch != "",
		})
		return
	}
	writeJSON(w, storage.listRoleFuncsets(branch, role))
}

func handleRoleFuncsetAdd(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)
	branch := strings.TrimSpace(r.FormValue("branch"))
	role := strings.TrimSpace(r.FormValue("role"))
	funcset := strings.TrimSpace(r.FormValue("funcset"))
	if r.Method == http.MethodGet || branch == "" || role == "" || funcset == "" {
		writeJSON(w, map[string]interface{}{
			"result":           true,
			"branchList":       storageBranches(),
			"branchInit":       branch,
			"branchAutoSubmit": role == "",
			"rolesList":        storage.listRoles4Branch(branch),
			"roleRequired":     branch != "",
			"funcSets":         storageFuncsets(),
		})
		return
	}
	writeJSON(w, storage.roleFuncsetAdd(branch, role, funcset))
}

func handleRoleFuncsetRemove(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)
	branch := strings.TrimSpace(r.FormValue("branch"))
	role := strings.TrimSpace(r.FormValue("role"))
	funcset := strings.TrimSpace(r.FormValue("funcset"))
	if r.Method == http.MethodGet || branch == "" || role == "" || funcset == "" {
		var roleFuncsets []interface{}
		if branch != "" && role != "" {
			if tmp := storage.listRoleFuncsets(branch, role); tmp != nil {
				if funcs, ok := tmp["funcsets"].([]string); ok {
					for _, v := range funcs {
						roleFuncsets = append(roleFuncsets, v)
					}
				}
			}
		}
		writeJSON(w, map[string]interface{}{
			"result":           true,
			"branchList":       storageBranches(),
			"branchInit":       branch,
			"branchAutoSubmit": role == "",
			"rolesList":        storage.listRoles4Branch(branch),
			"roleRequired":     branch != "",
			"roleInit":         role,
			"roleAutoSubmit":   funcset == "",
			"funcSets":         roleFuncsets,
			"funcSetRequired":  branch != "" && role != "",
		})
		return
	}
	writeJSON(w, storage.roleFuncsetRemove(branch, role, funcset))
}

func handleBranchSubs(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	branch := strings.TrimSpace(r.FormValue("branch"))
	if branch == "" {
		writeJSON(w, map[string]interface{}{
			"result":           true,
			"formMethod":       "get",
			"branchList":       storageBranches(),
			"branchCanBeEmpty": true,
			"label4Branch":     "Parent branch (or leave empty for root)",
		})
		return
	}
	writeJSON(w, storage.getBranchSubs(branch))
}

func handleBranchSubAdd(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)
	branch := strings.TrimSpace(r.FormValue("branch"))
	subbranch := strings.TrimSpace(r.FormValue("subbranch"))
	if r.Method == http.MethodGet {
		writeJSON(w, map[string]interface{}{
			"result":            true,
			"formMethod":        "post",
			"branchList":        storageBranches(),
			"label4Branch":      "Parent branch",
			"subBranchRequired": true,
		})
		return
	}
	writeJSON(w, storage.addBranchSub(branch, subbranch))
}

func handleBranchDelete(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)
	branch := strings.TrimSpace(r.FormValue("branch"))
	if r.Method == http.MethodGet {
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"branchList": storageBranches(),
		})
		return
	}
	writeJSON(w, storage.deleteBranch(branch))
}

func handleBranchWhiteListGet(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	branch := strings.TrimSpace(r.FormValue("branch"))
	if branch == "" {
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"branchList": storageBranches(),
		})
		return
	}
	writeJSON(w, storage.getBranchFsWhiteList(branch))
}

func handleBranchWhiteListSet(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)
	if r.Method == http.MethodGet {
		branch := strings.TrimSpace(r.FormValue("branch"))
		init := map[string]interface{}{}
		if branch != "" {
			init = storage.getBranchFsWhiteList(branch)
		}
		writeJSON(w, map[string]interface{}{
			"result":           true,
			"branchList":       storageBranches(),
			"branchInit":       branch,
			"branchAutoSubmit": branch == "",
			"funcSets":         storageFuncsets(),
			"init":             init,
		})
		return
	}
	branch := strings.TrimSpace(r.FormValue("branch"))
	propagateParent := boolFromParam(r.FormValue("propparent"), false)
	newWhiteList := r.Form["white"]
	writeJSON(w, storage.setBranchFsWhiteList(branch, propagateParent, newWhiteList))
}

func handleBranchRolesList(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	branch := strings.TrimSpace(r.FormValue("branch"))
	inherited := boolFromParam(r.FormValue("inherited"), false)
	withBranchIds := boolFromParam(r.FormValue("withbranchids"), false)
	if branch == "" {
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"branchList": storageBranches(),
			"cboxes": [][2]string{
				{"inherited", "Include inherited roles"},
				{"withbranchids", "Report also branch IDs"},
			},
		})
		return
	}
	writeJSON(w, storage.listBranchRoles(branch, inherited, withBranchIds))
}

func handleBranchRoleDelete(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)
	branch := strings.TrimSpace(r.FormValue("branch"))
	role := strings.TrimSpace(r.FormValue("role"))
	if r.Method == http.MethodGet || branch == "" || role == "" {
		writeJSON(w, map[string]interface{}{
			"result":           true,
			"branchList":       storageBranches(),
			"branchInit":       branch,
			"branchAutoSubmit": role == "",
			"rolesList":        storage.listRoles4Branch(branch),
			"roleRequired":     branch != "",
			"formMethod":       "post",
		})
		return
	}
	writeJSON(w, storage.deleteBranchRole(branch, role))
}

func handleBranchRoleCreate(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)
	branch := strings.TrimSpace(r.FormValue("branch"))
	role := strings.TrimSpace(r.FormValue("role"))
	duties := r.Form["duties"]
	if r.Method == http.MethodGet || branch == "" || role == "" {
		writeJSON(w, map[string]interface{}{
			"result":           true,
			"formMethod":       "post",
			"branchList":       storageBranches(),
			"branchInit":       branch,
			"branchAutoSubmit": branch == "",
			"roleRequired":     branch != "",
			"funcSets":         storageFuncsets(),
			"enabledFuncSets":  storage.getBranchEnabledFuncsets(branch),
		})
		return
	}
	writeJSON(w, storage.createBranchRole(branch, role, duties))
}

func handleAgentRegister(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)
	if r.Method == http.MethodGet {
		allBranches := []string{"*ROOT*"}
		allBranches = append(allBranches, storageBranches()...)
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"formMethod": "post",
			"branchList": allBranches,
			"extratxtinputs": [][3]string{
				{"descr", "Description", ""},
				{"location", "Location", ""},
				{"tags", "Tags (comma separated)", ""},
				{"extraxml", "Optional info in free XML format", ""},
			},
		})
		return
	}
	branch := strings.TrimSpace(r.FormValue("branch"))
	agent := strings.TrimSpace(r.FormValue("agent"))
	descr := r.FormValue("descr")
	location := r.FormValue("location")
	tags := r.FormValue("tags")
	extraxml := r.FormValue("extraxml")
	writeJSON(w, storage.registerAgentInBranch(branch, agent, false, descr, location, tags, extraxml))
}

func handleAgentMoveDown(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)
	branch := strings.TrimSpace(r.FormValue("branch"))
	agent := strings.TrimSpace(r.FormValue("agent"))
	descr := r.FormValue("descr")
	location := r.FormValue("location")
	tags := r.FormValue("tags")
	extraxml := r.FormValue("extraxml")
	if r.Method == http.MethodGet || branch == "" || agent == "" {
		ini := map[string]string{
			"descr":    "",
			"extra":    "",
			"location": "",
			"tags":     "",
		}
		if agent != "" {
			if ag := storage.agentDetailsJson(agent); ag["result"] == true {
				if details, ok := ag["details"].(map[string]interface{}); ok {
					if v, ok := details["descr"].(string); ok {
						ini["descr"] = v
					}
					if v, ok := details["location"].(string); ok {
						ini["location"] = v
					}
					if v, ok := details["tags"].(string); ok {
						ini["tags"] = v
					}
					if v, ok := details["extra"].(string); ok {
						ini["extra"] = v
					}
				}
			}
		}
		branchesForAgent := []string{}
		if agent != "" {
			branchesForAgent = storage.getSubBranchesOfAgent(agent)
		}
		writeJSON(w, map[string]interface{}{
			"result":          true,
			"formMethod":      "post",
			"agentsList":      storage.getAgents(),
			"agentInit":       agent,
			"agentAutoSubmit": branch == "",
			"branchList":      branchesForAgent,
			"extratxtinputs": [][3]string{
				{"descr", "Description", ini["descr"]},
				{"location", "Location", ini["location"]},
				{"tags", "Tags (comma separated)", ini["tags"]},
				{"extraxml", "Optional info in free XML format", ini["extra"]},
			},
		})
		return
	}
	writeJSON(w, storage.registerAgentInBranch(branch, agent, true, descr, location, tags, extraxml))
}

func handleAgentUnregister(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)
	if r.Method == http.MethodGet {
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"formMethod": "post",
			"agentsList": storage.getAgents(),
		})
		return
	}
	agent := strings.TrimSpace(r.FormValue("agent"))
	writeJSON(w, storage.unregisterAgent(agent))
}

func handleAgentDetailsXML(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	agent := strings.TrimSpace(r.FormValue("agent"))
	if agent == "" {
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"formMethod": "get",
			"agentsList": storage.getAgents(),
		})
		return
	}

	details := storage.agentDetailsXml(agent)
	if !details["result"].(bool) {
		writeJSON(w, details)
		return
	}
	writeXML(w, fmt.Sprintf("%v", details["details"]), http.StatusOK)
}

func handleAgentDetailsJson(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	agent := strings.TrimSpace(r.FormValue("agent"))
	if agent == "" {
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"formMethod": "get",
			"agentsList": storage.getAgents(),
		})
		return
	}
	writeJSON(w, storage.agentDetailsJson(agent))
}

func handleListAgents(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	branch := strings.TrimSpace(r.FormValue("branch"))
	withSubs := boolFromParam(r.FormValue("subsidinaries"), false)
	withLoc := boolFromParam(r.FormValue("location"), false)
	if branch == "" {
		writeJSON(w, map[string]interface{}{
			"result":     true,
			"branchList": append([]string{"*ALL*"}, storageBranches()...),
			"cboxes": [][2]string{
				{"subsidinaries", "Including subsidinaries"},
				{"location", "With location branch"},
			},
		})
		return
	}
	writeJSON(w, storage.listAgents(branch, withSubs, withLoc))
}

func handleFunctionTagsetModify(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet, http.MethodPost) {
		return
	}
	parseRequestForm(r)
	if r.Method == http.MethodGet {
		writeJSON(w, map[string]interface{}{
			"result":       true,
			"formMethod":   "post",
			"funcRequired": true,
			"funcList":     storageFunctionIDs(),
		})
		return
	}
	funcID := strings.TrimSpace(r.FormValue("funcId"))
	method := strings.TrimSpace(r.FormValue("method"))
	tagset := r.Form["tag"]
	writeJSON(w, storage.modifyFuncTagset(funcID, method, tagset, false))
}

func handleFunctionTagsetTest(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	funcID := strings.TrimSpace(r.FormValue("funcId"))
	method := strings.TrimSpace(r.FormValue("method"))
	tagset := r.Form["tag"]
	if funcID == "" || method == "" {
		writeJSON(w, map[string]interface{}{
			"result":       true,
			"formMethod":   "get",
			"funcRequired": true,
			"funcList":     storageFunctionIDs(),
			"readOnly":     true,
		})
		return
	}
	writeJSON(w, storage.modifyFuncTagset(funcID, method, tagset, true))
}

func handleTestRunnerStates(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	taskID := strings.TrimSpace(r.FormValue("poll"))
	if taskID != "" {
		writeJSON(w, checkTask(taskID))
		return
	}

	durationRaw := r.FormValue("durationEach")
	dur, _ := strconv.Atoi(durationRaw)
	states := splitCSV(r.FormValue("states"))
	finalMessage := r.FormValue("final")
	agentID := r.FormValue("agent")
	taskId := runTestSteadyStepsWithFinMsg(states, dur, finalMessage, agentID)

	time.Sleep(time.Second)
	writeJSON(w, checkTask(taskId))
}

func handleBranches(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	writeJSON(w, map[string]interface{}{
		"result": true,
		"data":   storage.getBranches(""),
	})
}

func handlePositions(w http.ResponseWriter, r *http.Request) {
	if !ensureMethods(w, r.Method, http.MethodGet) {
		return
	}
	parseRequestForm(r)
	filter := strings.TrimSpace(r.FormValue("filter"))
	writeJSON(w, map[string]interface{}{
		"result": true,
		"data":   storage.getPositions(filter),
	})
}

func route(mux *http.ServeMux, path string, handler http.HandlerFunc) {
	mux.Handle(path, withCORS(http.HandlerFunc(handler)))
}

func main() {
	cfgPath, err := firstExisting(filepath.Join("..", "config", "general.yaml"), filepath.Join("config", "general.yaml"))
	if err != nil {
		cfgPath, _ = filepath.Abs("../config/general.yaml")
	}
	cfg, err := loadAppConfig(cfgPath)
	if err != nil {
		fmt.Printf("failed to read config %s: %v\n", cfgPath, err)
		return
	}

	runAt := parseRunAt(os.Args[1:], cfg.DefaultRunLocation)
	runLocation, ok := cfg.RunLocations[runAt]
	if !ok {
		runAt = cfg.DefaultRunLocation
		runLocation = cfg.RunLocations[runAt]
	}

	corsWhitelist = map[string]struct{}{}
	for _, item := range runLocation.CorsWhitelist {
		corsWhitelist[item] = struct{}{}
	}

	dataDir, err := firstExisting(filepath.Join("..", "DATA"), "DATA", filepath.Join("aac", "DATA"), filepath.Join("..", "aac", "DATA"))
	if err != nil {
		fmt.Printf("failed to locate DATA directory: %v\n", err)
		return
	}
	storage = newConfigDataKeeper(dataDir, cfg.SessionMaxDefault)
	if err := storage.load(); err != nil {
		fmt.Printf("failed to load data keeper: %v\n", err)
		return
	}

	staticDir, err := firstExisting(filepath.Join("..", "aac", "static"), filepath.Join("aac", "static"), filepath.Join("static"))
	if err != nil {
		fmt.Printf("failed to locate static directory: %v\n", err)
		return
	}

	mux := http.NewServeMux()
	fileServer := http.FileServer(http.Dir(staticDir))

	route(mux, "/", handleRouteRoot)
	route(mux, "/index.html", handleRouteRoot)
	route(mux, "/aac", handleAacRoot)
	route(mux, "/aac/", handleAacRoot)
	route(mux, "/aac/static/index.html", handleRouteRoot)
	mux.Handle("/aac/static/", withCORS(http.StripPrefix("/aac/static/", fileServer)))

	route(mux, "/aac/authentificate", handleAuthorize)
	route(mux, "/aac/authorize", handleAuthorize)
	route(mux, "/aac/user/create", handleUserCreate)
	route(mux, "/aac/user/change", handleUserChange)
	route(mux, "/aac/user/details", handleUserDetails)
	route(mux, "/aac/users/list", handleUsersList)
	route(mux, "/aac/functions/list", handleFunctionsList)
	route(mux, "/aac/function/review", handleFunctionReview)
	route(mux, "/aac/functions/review", handleFunctionReview)
	route(mux, "/aac/user/delete", handleUserDelete)
	route(mux, "/aac/hr/fire", handleEmployeeFire)
	route(mux, "/aac/hr/hire", handleEmployeeHire)
	route(mux, "/aac/hr/branch/position/create", handleCreateBranchPosition)
	route(mux, "/aac/hr/branch/position/delete", handleDeleteBranchPosition)
	route(mux, "/aac/emp/subbranches/list", handleEmpSubBranches)
	route(mux, "/aac/emp/funcsets/list", handleEmpFuncsets)
	route(mux, "/aac/emp/functions/list", handleEmpFunctionsList)
	route(mux, "/aac/emp/functions/review", handleEmpFunctionsReview)
	route(mux, "/aac/branch/employees/list", handleBranchEmployeesList)
	route(mux, "/aac/hr/branch/positions", handleHrPositions)
	route(mux, "/aac/function/info", handleFunctionInfo)
	route(mux, "/aac/function/delete", handleFunctionDelete)
	route(mux, "/aac/function/upload/xmldescr", handleFunctionUploadXmlDescr)
	route(mux, "/aac/function/upload/xmlfile", handleFunctionUploadXmlFile)
	route(mux, "/aac/funcsets", handleFuncsets)
	route(mux, "/aac/funcset/create", handleFuncsetCreate)
	route(mux, "/aac/funcset/delete", handleFuncsetDelete)
	route(mux, "/aac/funcset/details", handleFuncsetDetails)
	route(mux, "/aac/funcset/function/add", handleFuncsetFunctionAdd)
	route(mux, "/aac/funcset/function/remove", handleFuncsetFunctionRemove)
	route(mux, "/aac/role/funcsets", handleRoleFuncsets)
	route(mux, "/aac/role/funcset/add", handleRoleFuncsetAdd)
	route(mux, "/aac/role/funcset/remove", handleRoleFuncsetRemove)
	route(mux, "/aac/branch/subbranches", handleBranchSubs)
	route(mux, "/aac/branch/subbranch/add", handleBranchSubAdd)
	route(mux, "/aac/branch/delete", handleBranchDelete)
	route(mux, "/aac/branch/fswhitelist/get", handleBranchWhiteListGet)
	route(mux, "/aac/branch/fswhitelist/set", handleBranchWhiteListSet)
	route(mux, "/aac/branch/roles/list", handleBranchRolesList)
	route(mux, "/aac/branch/role/delete", handleBranchRoleDelete)
	route(mux, "/aac/branch/role/create", handleBranchRoleCreate)
	route(mux, "/aac/agent/register", handleAgentRegister)
	route(mux, "/aac/agent/movedown", handleAgentMoveDown)
	route(mux, "/aac/agent/unregister", handleAgentUnregister)
	route(mux, "/aac/agent/details/xml", handleAgentDetailsXML)
	route(mux, "/aac/agent/details/json", handleAgentDetailsJson)
	route(mux, "/aac/agents/list", handleListAgents)
	route(mux, "/aac/function/tagset/modify", handleFunctionTagsetModify)
	route(mux, "/aac/function/tagset/test", handleFunctionTagsetTest)
	route(mux, "/aac/testrunner/states", handleTestRunnerStates)
	route(mux, "/aac/branches", handleBranches)
	route(mux, "/aac/positions", handlePositions)

	addr := fmt.Sprintf(":%d", runLocation.Port)
	fmt.Printf("AAC Go is running on port %d (run location: %s)\n", runLocation.Port, runAt)
	if err := http.ListenAndServe(addr, mux); err != nil {
		fmt.Printf("server failed: %v\n", err)
	}
}
