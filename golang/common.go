package main

import (
    "encoding/json"
    "fmt"
    "net/http"
    "regexp"
    "sort"
    "strconv"
    "strings"
)

var reasonCode = map[string]int{
    "WRONG-FORMAT": 400,
    "WRONG-DATA": 400,
    "USER-UNKNOWN": 401,
    "WRONG-SECRET": 403,
    "SECRET-EXPIRED": 403,
    "ALREADY-EXISTS": 403,
    "USER-EMPLOYED": 403,
    "ALREADY-UNEMPLOYED": 403,
    "FUNCTION-UNKNOWN": 404,
    "FUNCSET-UNKNOWN": 404,
    "ROLE-UNKNOWN": 404,
    "PROP-UNKNOWN": 404,
    "BRANCH-UNKNOWN": 404,
    "AGENT-UNKNOWN": 404,
    "NOT-IN-SET": 404,
    "NOT-ALLOWED": 405,
    "DATABASE-ERROR": 500,
    "OP-UNKNOWN": 401,
    "OP-UNAUTHORIZED": 401,
    "OPERATOR-UNKNOWN": 401,
    "FORBIDDEN-FOR-OP": 403,
}

var safeIDRe = regexp.MustCompile(`^[\p{L}\p{N}_\-.@+ ]{0,256}$`)

func httpCodeFor(payload map[string]interface{}) int {
    if payload == nil {
        return http.StatusOK
    }
    reason, ok := payload["reason"].(string)
    if !ok {
        return http.StatusOK
    }
    if c, ok := reasonCode[reason]; ok {
        return c
    }
    return http.StatusOK
}

func writeJSON(w http.ResponseWriter, payload map[string]interface{}) {
    code := httpCodeFor(payload)
    w.Header().Set("Content-Type", "application/json; charset=utf-8")
    w.WriteHeader(code)
    enc := json.NewEncoder(w)
    enc.SetIndent("", "  ")
    _ = enc.Encode(payload)
}

func uniqueStrings(values []string) []string {
    seen := make(map[string]struct{}, len(values))
    out := make([]string, 0, len(values))
    for _, v := range values {
        if _, ok := seen[v]; ok {
            continue
        }
        seen[v] = struct{}{}
        out = append(out, v)
    }
    sort.Strings(out)
    return out
}

func toInt(value string, fallback int) int {
    if value == "" {
        return fallback
    }
    i, err := strconv.Atoi(value)
    if err != nil {
        return fallback
    }
    return i
}

func toInt64(value string, fallback int64) int64 {
    if value == "" {
        return fallback
    }
    i, err := strconv.ParseInt(value, 10, 64)
    if err != nil {
        return fallback
    }
    return i
}

func splitCSV(input string) []string {
    return strings.Split(input, ",")
}

func safeXPathValue(v string) (string, error) {
    if !safeIDRe.MatchString(v) {
        return v, fmt.Errorf("Unsafe characters in identifier: %q", v)
    }
    return v, nil
}

func boolFromParam(value string, def bool) bool {
    v := strings.TrimSpace(strings.ToLower(value))
    if v == "" {
        return def
    }
    return v == "yes"
}

func mapSet(values ...string) map[string]struct{} {
    m := make(map[string]struct{}, len(values))
    for _, v := range values {
        m[v] = struct{}{}
    }
    return m
}

func intersectSets(a, b map[string]struct{}) []string {
    out := make([]string, 0)
    for k := range a {
        if _, ok := b[k]; ok {
            out = append(out, k)
        }
    }
    return uniqueStrings(out)
}
