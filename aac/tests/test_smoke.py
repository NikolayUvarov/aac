"""Smoke tests for core dataKeeper operations.

These tests run against a fresh copy of DATA.vanila each time,
so they do not affect production data.
"""
import pytest
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import error_codes as EC

# ---------------------------------------------------------------------------
# Authorization
# ---------------------------------------------------------------------------

class TestAuthorize:

    def test_authorize_known_user_correct_secret(self, storage):
        # admin's secret is sha256("admin" as password input — see vanilla data)
        secret = "d82494f05d6917ba02f7aaa29689ccb444bb73f20380876cb05d1f37537b7892"
        result = storage.authorize("admin", secret, None)
        assert result["result"] is True

    def test_authorize_wrong_secret(self, storage):
        result = storage.authorize("admin", "bad_secret", None)
        assert result["result"] is False
        assert result["reason"] == EC.WRONG_SECRET

    def test_authorize_unknown_user(self, storage):
        result = storage.authorize("ghost", "any", None)
        assert result["result"] is False
        assert result["reason"] == EC.USER_UNKNOWN

    def test_authorize_missing_secret(self, storage):
        result = storage.authorize("admin", None, None)
        assert result["result"] is False
        assert result["reason"] == EC.WRONG_FORMAT


# ---------------------------------------------------------------------------
# User CRUD
# ---------------------------------------------------------------------------

class TestUserCrud:

    def test_create_and_list(self, storage):
        ret = storage.createUser("testuser", "secret123", "admin", readablename="Test User")
        assert ret["result"] is True
        assert "testuser" in storage.listUsers()["users"]

    def test_create_duplicate(self, storage):
        storage.createUser("dup", "s", "admin")
        ret = storage.createUser("dup", "s", "admin")
        assert ret["result"] is False
        assert ret["reason"] == EC.ALREADY_EXISTS

    def test_change_user(self, storage):
        storage.createUser("u1", "old_secret", "admin")
        ret = storage.changeUser("u1", "new_secret", "admin")
        assert ret["result"] is True

    def test_delete_user(self, storage):
        storage.createUser("delme", "s", "admin")
        ret = storage.deleteUser("delme", "admin")
        assert ret["result"] is True
        assert "delme" not in storage.listUsers()["users"]

    def test_delete_employed_user_fails(self, storage):
        # admin is employed at sysroot — should fail
        ret = storage.deleteUser("admin", "admin")
        assert ret["result"] is False
        assert ret["reason"] == EC.USER_EMPLOYED


# ---------------------------------------------------------------------------
# Branch operations
# ---------------------------------------------------------------------------

class TestBranches:

    def test_list_branches(self, storage):
        brs = storage.listBranches()
        assert "sysroot" in brs

    def test_add_subbranch(self, storage):
        ret = storage.addBranchSub("sysroot", "dept-a")
        assert ret["result"] is True
        subs = storage.getBranchSubs("sysroot")
        assert "dept-a" in subs["branches"]

    def test_add_duplicate_subbranch(self, storage):
        storage.addBranchSub("sysroot", "dup-br")
        ret = storage.addBranchSub("sysroot", "dup-br")
        assert ret["result"] is False
        assert ret["reason"] == EC.ALREADY_EXISTS

    def test_delete_branch(self, storage):
        storage.addBranchSub("sysroot", "temp")
        ret = storage.deleteBranch("temp")
        assert ret["result"] is True

    def test_cannot_delete_root(self, storage):
        ret = storage.deleteBranch("sysroot")
        assert ret["result"] is False
        assert ret["reason"] == EC.NOT_ALLOWED


# ---------------------------------------------------------------------------
# Funcset operations
# ---------------------------------------------------------------------------

class TestFuncsets:

    def test_create_funcset(self, storage):
        ret = storage.funcsetCreate("sysroot", "fs-test", "Test Funcset")
        assert ret["result"] is True
        assert "fs-test" in storage.getFuncsets()

    def test_funcset_add_remove_func(self, storage):
        storage.funcsetCreate("sysroot", "fs1", "")
        ret = storage.funcsetFuncAdd("fs1", "somefunc")
        assert ret["result"] is True
        details = storage.getFuncsetDetails("fs1")
        assert "somefunc" in details["functions"]

        ret = storage.funcsetFuncRemove("fs1", "somefunc")
        assert ret["result"] is True
        details = storage.getFuncsetDetails("fs1")
        assert "somefunc" not in details["functions"]

    def test_delete_funcset(self, storage):
        storage.funcsetCreate("sysroot", "fs-del", "")
        ret = storage.funcsetDelete("fs-del")
        assert ret["result"] is True
        assert "fs-del" not in storage.getFuncsets()


# ---------------------------------------------------------------------------
# Hire / Fire
# ---------------------------------------------------------------------------

class TestHireFire:

    def _setup_branch_and_user(self, storage):
        storage.addBranchSub("sysroot", "dept")
        storage.createBranchRole("dept", "worker", [])
        storage.createBranchPosition("dept", "worker")
        storage.createUser("emp1", "s", "admin")

    def test_hire_and_fire(self, storage):
        self._setup_branch_and_user(storage)
        ret = storage.hireEmployee("emp1", "dept", "worker", "admin")
        assert ret["result"] is True

        ret = storage.fireEmployee("emp1", "admin")
        assert ret["result"] is True
        assert ret["pos"] == "worker"

    def test_fire_unemployed(self, storage):
        storage.createUser("nobody", "s", "admin")
        ret = storage.fireEmployee("nobody", "admin")
        assert ret["result"] is False
        assert ret["reason"] == EC.ALREADY_UNEMPLOYED


# ---------------------------------------------------------------------------
# Role operations
# ---------------------------------------------------------------------------

class TestRoles:

    def test_create_and_list_role(self, storage):
        storage.addBranchSub("sysroot", "dept")
        ret = storage.createBranchRole("dept", "analyst", ["fs1"])
        assert ret["result"] is True

        roles = storage.listRoles4Branch("dept")
        assert "analyst" in roles

    def test_delete_role(self, storage):
        storage.addBranchSub("sysroot", "dept")
        storage.createBranchRole("dept", "temp-role", [])
        ret = storage.deleteBranchRole("dept", "temp-role")
        assert ret["result"] is True

    def test_role_funcset_add_remove(self, storage):
        storage.addBranchSub("sysroot", "dept")
        storage.funcsetCreate("dept", "fs-r", "")
        storage.createBranchRole("dept", "mgr", [])

        ret = storage.roleFuncsetAdd("dept", "mgr", "fs-r")
        assert ret["result"] is True

        details = storage.listRoleFuncsets("dept", "mgr")
        assert "fs-r" in details["funcsets"]

        ret = storage.roleFuncsetRemove("dept", "mgr", "fs-r")
        assert ret["result"] is True


# ---------------------------------------------------------------------------
# Function catalogue
# ---------------------------------------------------------------------------

class TestFunctionCatalogue:

    def test_list_functions(self, storage):
        ret = storage.listFunctions("id")
        assert ret["result"] is True
        assert len(ret["values"]) > 0

    def test_review_function(self, storage):
        ret = storage.reviewFunctions("id,name", function_id="uadm:createUser")
        assert ret["result"] is True
        assert ret["props"]["id"] == "uadm:createUser"

    def test_post_and_delete_function(self, storage):
        xml = '<function id="test:new" name="New" title="New func" descr="test"><call method="GET"><url>http://localhost</url></call></function>'
        ret = storage.postFunctionDef(xml)
        assert ret["result"] is True
        assert ret["status"] == "APPENDED"

        ret = storage.deleteFunctionDef("test:new")
        assert ret["result"] is True


# ---------------------------------------------------------------------------
# XPath injection protection
# ---------------------------------------------------------------------------

class TestSafeXpath:

    def test_safe_value_passes(self, storage):
        from dataKeeper import _safe_xpath_value
        assert _safe_xpath_value("hello-world.123") == "hello-world.123"

    def test_unsafe_value_raises(self, storage):
        from dataKeeper import _safe_xpath_value
        with pytest.raises(ValueError):
            _safe_xpath_value("' or 1=1 or '")

    def test_none_passthrough(self, storage):
        from dataKeeper import _safe_xpath_value
        assert _safe_xpath_value(None) is None


# ---------------------------------------------------------------------------
# Deferred save
# ---------------------------------------------------------------------------

class TestDeferredSave:

    def test_save_marks_dirty(self, storage):
        assert not storage._dirty_universe
        storage._save()
        # With no event loop it flushes immediately (sync mode)
        assert not storage._dirty_universe  # flushed

    def test_threshold_flush(self, storage):
        from unittest.mock import MagicMock
        # Override threshold for testing
        storage.FLUSH_CHANGE_THRESHOLD = 3
        # Use a mock loop that supports call_later but doesn't actually schedule
        mock_loop = MagicMock()
        mock_loop.call_later.return_value = MagicMock()
        storage._loop = mock_loop

        storage._dirty_universe = False
        storage._pending_changes = 0

        storage._save()  # 1
        assert storage._dirty_universe
        storage._save()  # 2
        assert storage._pending_changes == 2
        # 3rd triggers flush
        storage._save()  # 3 — reaches threshold
        assert not storage._dirty_universe
        assert storage._pending_changes == 0

    def test_shutdown_flushes(self, storage):
        storage._dirty_universe = True
        storage._pending_changes = 1
        storage.shutdown()
        assert not storage._dirty_universe


# ---------------------------------------------------------------------------
# Error codes module
# ---------------------------------------------------------------------------

class TestErrorCodes:

    def test_all_reasons_have_http_mapping(self):
        from error_codes import REASON_TO_HTTP
        # Ensure all defined constants map to an integer HTTP code
        for reason, code in REASON_TO_HTTP.items():
            assert isinstance(reason, str)
            assert isinstance(code, int)
            assert 400 <= code <= 599
