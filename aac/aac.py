# aac.py

import yaml
import asyncio
import sys
#from random import random
import json

import hashlib
#print(hashlib.algorithms_guaranteed)

from functools import wraps

#--------------------------------------------------------------------------------------------------------------

import logging
import logging.config
logger = logging.getLogger("aac")

#----------------------------------------------------------------------------

from dataKeeper import configDataKeeper
storage = None # to be set in main by configDataKeeper

#----------------------------------------------------------------------------

import testRunner

#----------------------------------------------------------------------------

import quart as fwrk # using fwrk alias to minimize code diff with Flask
from quart import websocket
app = fwrk.Quart(
    __name__,
    static_url_path="/aac/static", # with leading slash - Quart requirement
    static_folder="aac/static",  # without leading slash - important!
)

#----------------------------------------------------------------------------

def hashString2Hex(input):
    byte_input = input.encode()
    hash_object = hashlib.sha256(byte_input)
    return hash_object.hexdigest()

#----------------------------------------------------------------------------
# The root page (technical index)

@app.route('/')
@app.route('/index.html')
@app.route('/aac')
@app.route('/aac/')
@app.route('/aac/static/index.html')
async def index():

    return (fwrk.redirect(fwrk.url_for('static', filename='techIndex.html') ))

#----------------------------------------------------------------------------

# A decorator to remove some repeating wrapping from request handlers:
def aac_rq_handler(afunc):
    @wraps(afunc)
    async def wrapped(*args, **kwargs):

        logger.info(f"Request is {fwrk.request}, content type {repr(fwrk.request.content_type)}")
        logger.debug( "Request cookies: " + ",".join( f"{x}:{repr(fwrk.request.cookies[x])}" for x in fwrk.request.cookies ) )

        logRet,ret = await afunc(*args, **kwargs)

        if logRet:
            logger.info(f"Result is {ret}")
        return ret
    return wrapped

#----------------------------------------------------------------------------

def add_respcode_by_reason( some_dict ):
    rspCode = { 
                "WRONG-FORMAT"       :400,
                "WRONG-DATA"         :400,
                "USER-UNKNOWN"       :401, # user is a special case - returning "Unathorized"
                "WRONG-SECRET"       :403,
                "SECRET-EXPIRED"     :403,
                "ALREADY-EXISTS"     :403,
                "USER-EMPLOYED"      :403,
                "ALREADY-UNEMPLOYED" :403,                
                "FUNCTION-UNKNOWN"   :404, # for the most of "unknown" cases returning "Not found" 
                "FUNCSET-UNKNOWN"    :404,
                "ROLE-UNKNOWN"       :404,
                "PROP-UNKNOWN"       :404,
                "BRANCH-UNKNOWN"     :404,
                "AGENT-UNKNOWN"      :404,
                "NOT-IN-SET"         :404,
                "NOT-ALLOWED"        :405,
                "DATABASE-ERROR"     :500,
                "OP-UNAUTHORIZED"    :401, # operator needs to login
                "OPERATOR-UNKNOWN"   :401, # may happen if operator was removed from database while his authorization still active
                "FORBIDDEN-FOR-OP"   :403, 

              }.get(some_dict.get("reason",None),200)
    return (some_dict, rspCode, {'Content-Type':'application/json; charset=utf-8'})

#----------------------------------------------------------------------------

def _get_operator_id():
    gAPuser = fwrk.request.headers.get("X-RDSC-username",None)
    gAPuuid = fwrk.request.cookies.get("uuid","")
    if not gAPuser is None and len(gAPuuid)>0:
        return gAPuser
    return fwrk.request.cookies.get("rdsc-userid",None)

#----------------------------------------------------------------------------

@app.route('/aac/authentificate', methods=["POST", "GET"])
@app.route('/aac/authorize', methods=["POST", "GET"])
@aac_rq_handler
async def authorize():

    #form = await fwrk.request.form
    values = await fwrk.request.values #combination of url and form parameters
    for a in values.keys():
       logger.info(f"--- {repr(a)} : {repr(values[a])}")

    if not all(x in values for x in ("username","secret")):
        return (False, await fwrk.render_template( 'form4_userAndPass.jinja', userList = storage.listUsers()["users"]  ))

    logger.debug(f"Request path is {fwrk.request.path}, full path {fwrk.request.full_path}")
    app_name = None if fwrk.request.path=="/aac/authentificate" else fwrk.request.args.get("app","")
    logger.info(f"app name is {app_name}")

    username = values["username"] # here we know we have it
    secret = values["secret"]

    authrez = storage.authorize(username,secret,app_name)
    resp = await fwrk.make_response(add_respcode_by_reason(authrez))
    logger.info(f"response made is is {repr(resp)}")

    return ( True, resp )

#----------------------------------------------------------------------------

@app.route('/aac/user/create', methods=["POST", "GET"])
@aac_rq_handler
async def user_create():

    if fwrk.request.method == "GET":
        return (False, await fwrk.render_template( 'form4_userReg.jinja', 
                                                   operList = storage.listUsers()["users"], 
                                                   init={ 'sessionMax':cfgDict["session_max_default"], } 
                                                 ))
    form = await fwrk.request.form
    username,secret,pswLifeTime,rname,sessmax,op = ( form.get(x,None) for x in ("username","secret","pswlifetime","readablename","sessionmax","operator") )
    return ( True, add_respcode_by_reason(storage.createUser(username,secret,op,pswLifeTime,rname,sessmax )) )


#----------------------------------------------------------------------------

@app.route('/aac/user/change', methods=["POST", "GET"])
@aac_rq_handler
async def user_change():

    form = await fwrk.request.form
    username,secret,pswLifeTime,rname,sessmax,op = ( form.get(x,"") for x in ("username","secret","pswlifetime","readablename","sessionmax","operator") )

    if secret=="":
        uList = storage.listUsers()
        olddata = {} if username =="" else storage.get_user_reg_details(username)
        return (False, await fwrk.render_template( 'form4_userReg.jinja', 
                                                   userList = uList["users"], 
                                                   operList = uList["users"], 
                                                   init = olddata if olddata.get('result',False) else {},
                                                   userAutoSubmit = secret=="",
                                                   useridInit = username,
                                                 ))
                               
    return ( True, add_respcode_by_reason(storage.changeUser(username,secret,op,pswLifeTime,rname,sessmax )) )

#----------------------------------------------------------------------------

@app.route('/aac/user/details')
@aac_rq_handler
async def user_details():
    values = await fwrk.request.values #combination of url and form parameters
    username = values.get("username",None)
    app = values.get("app","")
    if username is None:
        return (False, await fwrk.render_template( 'form4_userAndApp.jinja', userList = storage.listUsers()["users"] ))
    return ( True, add_respcode_by_reason(storage.get_user_reg_details(username,app)) )

#----------------------------------------------------------------------------

@app.route('/aac/users/list', methods=["GET"])
@aac_rq_handler
async def users_list():
    return (True, storage.listUsers())

#----------------------------------------------------------------------------

@app.route('/aac/functions/list', methods=["GET"])
@aac_rq_handler
async def functions_list():

    prop = fwrk.request.args.get("prop",default=None)

    if prop is None:
        return (False, await fwrk.render_template( 'form4_funcprop.jinja' ))

    return (True, add_respcode_by_reason(storage.listFunctions(prop)) )

#----------------------------------------------------------------------------

@app.route('/aac/function/review', methods=["GET"])
@app.route('/aac/functions/review', methods=["GET"])
@aac_rq_handler
async def functions_review():

    props = fwrk.request.args.get("props",default=None)
    if fwrk.request.path == "/aac/functions/review":
        # Behaviour matches Go/Elixir: this path is used as a "list" variant.
        return (True, {'result': True})

    function_id = fwrk.request.args.get("funcId",default=None)

    if props is None or function_id in (None, ""):
        return (False, await fwrk.render_template( 'form4_funcprops.jinja',
                                                   funcList = storage.listFunctions("id")["values"]
                                                 ) )

    return (True,  add_respcode_by_reason(storage.reviewFunctions(props,function_id)) )

#----------------------------------------------------------------------------
                                            
@app.route('/aac/user/delete', methods=["POST", "GET"])
@aac_rq_handler
async def user_delete():
    if fwrk.request.method == "GET":
        uList = storage.listUsers()
        return (False, await fwrk.render_template( 'form4_user.jinja', formMethod='post', 
                                                   userList = uList["users"],
                                                   operList = uList["users"],
                                                   operatorDriven = True,
                                                 ))
    form = await fwrk.request.form
    username,operator =  (form.get(x,None) for x in ("username","operator"))
    return ( True, add_respcode_by_reason(storage.deleteUser(username,operator)) )

#----------------------------------------------------------------------------

@app.route('/aac/hr/fire', methods=["POST", "GET"])
@aac_rq_handler
async def employee_fire():
    if fwrk.request.method == "GET":
        uList = storage.listUsers()
        return (False, await fwrk.render_template( 'form4_user.jinja', formMethod='post', 
                                                   userList = uList["users"],
                                                   operList = uList["users"],
                                                   operatorDriven = True,
                                                 ))
    form = await fwrk.request.form
    username,operator =  (form.get(x,None) for x in ("username","operator"))
    return ( True, add_respcode_by_reason( storage.fireEmployee(username, operator) ) )

#----------------------------------------------------------------------------

@app.route('/aac/hr/hire', methods=["POST", "GET"])
@aac_rq_handler
async def employee_hire():

    form = await fwrk.request.form
    u,b,p,operator = (form.get(x,default="") for x in ("username","branch","position","operator"))

    if fwrk.request.method == "GET" or b=="" or p=="":
        uList = storage.listUsers()
        return (False, await fwrk.render_template( 'form4_userBranchPos.jinja', 
                                                   userList = uList["users"],
                                                   branchReview = storage.reviewBranches(p),
                                                   posReview = storage.reviewPositions(b),
                                                   init = {'u':u,'b':b,'p':p},
                                                   operList = uList["users"],
                                                 ))

    return (True, add_respcode_by_reason(storage.hireEmployee(u,b,p, operator)))

#----------------------------------------------------------------------------

@app.route('/aac/hr/branch/position/create', methods=["POST", "GET"])
@aac_rq_handler
async def branch_pos_create():

    form = await fwrk.request.form
    branch,role = (form.get(x,default="") for x in ("branch","role"))

    if branch=="" or role=="":
        return (False, await fwrk.render_template( 'form4_branchRole.jinja', formMethod='post', 
                                                   branchList = storage.listBranches(),                                                   
                                                   branchInit = branch,
                                                   branchAutoSubmit = role=="",

                                                   rolesList = storage.listEnabledRoles4Branch(branch) if branch!="" else (),
                                                   roleRequired = branch!="",
                                                 )
               )
    return (True, add_respcode_by_reason(storage.createBranchPosition(branch,role)))

#----------------------------------------------------------------------------

@app.route('/aac/hr/branch/position/delete', methods=["POST", "GET"])
@aac_rq_handler
async def branch_pos_delete():

    form = await fwrk.request.form
    branch,role = (form.get(x,default="") for x in ("branch","role"))

    if branch=="" or role=="":
        return (False, await fwrk.render_template( 'form4_branchRole.jinja', formMethod='post', 
                                                   branchList = storage.listBranches(),                                                   
                                                   branchInit = branch,
                                                   branchAutoSubmit = role=="",

                                                   rolesList = storage.getBranchVacantPositions(branch) if branch!="" else (),
                                                   roleRequired = branch!="",
                                                 )
               )
    return (True, add_respcode_by_reason(storage.deleteBranchPosition(branch,role)))

#----------------------------------------------------------------------------

@app.route('/aac/emp/subbranches/list', methods=["GET"])
@aac_rq_handler
async def emp_subbranches_list():

    username = fwrk.request.args.get("username",default=None)
    allLevels = fwrk.request.args.get("allLevels",default="yes")
    excludeOwn = fwrk.request.args.get("excludeOwn",default="no")
    if username==None: 
        return (False, await fwrk.render_template( 'form4_userAndChild.jinja', userList = storage.listUsers()["users"] ))
    else:
        return (True, storage.empSubbranchesList(username,allLevels=='yes',excludeOwn=='yes'))


#----------------------------------------------------------------------------

@app.route('/aac/emp/funcsets/list', methods=["GET"])
@aac_rq_handler
async def emp_funcsets_list():
    username = fwrk.request.args.get("username",None)
    if username is None:
        return (False, await fwrk.render_template( 'form4_user.jinja', userList = storage.listUsers()["users"], formMethod='get' ))
    return ( True, add_respcode_by_reason(storage.empFuncsetsList(username)) )

#----------------------------------------------------------------------------

@app.route('/aac/emp/functions/list', methods=["GET"])
@aac_rq_handler
async def emp_functions_list():

    username = fwrk.request.args.get("username",default=None)
    prop = fwrk.request.args.get("prop",default="id")

    if username is None: 
        return (False, await fwrk.render_template( 'form4_funcprop.jinja', userList = storage.listUsers()["users"] ))

    return ( True, add_respcode_by_reason( storage.empFunctionsList(username,prop) ))

#----------------------------------------------------------------------------

@app.route('/aac/emp/functions/review', methods=["GET"])
@aac_rq_handler
async def emp_functions_review():

    username = fwrk.request.args.get("username",default=None)
    props = fwrk.request.args.get("props",default=None)

    if username is None or props is None: 
        return (False, await fwrk.render_template( 'form4_funcprops.jinja', userList = storage.listUsers()["users"] ))

    return ( True, add_respcode_by_reason( storage.empFunctionsReview(username,props) ))

#----------------------------------------------------------------------------

@app.route('/aac/branch/employees/list', methods=["GET"])
@aac_rq_handler
async def branch_employees_list():

    branchId = fwrk.request.args.get("branch",default="")
    includeSubBranches = fwrk.request.args.get("includeSubBranches",default="no")
    if branchId=="": 
        return (False, await fwrk.render_template( 'form4_branchExt.jinja' , 
                                                   branchList = storage.listBranches(),
                                                   cboxes=( ("includeSubBranches","Include sub-branches"),
                                                          )
                                                 ))
    else:
        return (True, storage.branchEmployeesList(branchId,includeSubBranches=='yes'))


#----------------------------------------------------------------------------

@app.route('/aac/hr/branch/positions', methods=["GET"])
@aac_rq_handler
async def branch_hr_positions():

    branch_id = fwrk.request.args.get("branch",default=None)
    per_role,only_vacant = (fwrk.request.args.get(x,default="no") for x in ("perRole","onlyVacant"))

    if branch_id is None: 
        return (False, await fwrk.render_template( 'form4_branchExt.jinja' , 
                                                   branchList = ["*ALL*"] + storage.listBranches(),
                                                   cboxes=( ("perRole","Per-role report",True),
                                                            ("onlyVacant","Report only vacant positions",True),
                                                          )
                                                 ))
    else:
        return (True, storage.get_branches_with_positions(branch_id,per_role=='yes',only_vacant=='yes'))


#----------------------------------------------------------------------------

@app.route('/aac/function/info', methods=["GET"])
@aac_rq_handler
async def funcInfo():

    functionId = fwrk.request.args.get("funcId",default="")
    pure = fwrk.request.args.get("pure",default="no")
    xsltref = fwrk.request.args.get("xsltref",default="")
    if functionId=="": 
        return (False, await fwrk.render_template( 'form4_funcXslt.jinja', 
                                                   funcRequired = True, 
                                                   funcList = storage.listFunctions("id")["values"]
                                                 ))
    from xml.sax.saxutils import quoteattr
    hdr = '' if xsltref=='' else f'<?xml version="1.0" encoding="UTF-8"?>\n<?xml-stylesheet type="text/xsl" href={quoteattr(xsltref)}?>\n\n'
    tmp = storage.getFunctionDef(functionId,False,hdr)

    if pure=='yes' and tmp['result']:
        return ( True, (tmp["definition"], 200, {'Content-Type': 'text/xml; charset=utf-8'}))
    return add_respcode_by_reason(tmp)


#----------------------------------------------------------------------------

@app.route('/aac/function/delete', methods=["GET","POST"])
@aac_rq_handler
async def funcDelXmlDescr():

    if fwrk.request.method == "GET":
        return (False, await fwrk.render_template( 'form4_func.jinja' , 
                                                   funcRequired = True,
                                                   funcList = storage.listFunctions("id")["values"],
                                                   formMethod='post',
                                                 ))
    form = await fwrk.request.form
    functionId = form.get("funcId",default=None)

    return ( True, add_respcode_by_reason( storage.deleteFunctionDef(functionId) ))


#----------------------------------------------------------------------------

@app.route('/aac/function/upload/xmldescr', methods=["GET","POST"])
@aac_rq_handler
async def funcUpXmlDescr():

    if fwrk.request.method == "GET":
        return (False, await fwrk.render_template( 'form4_xmlDescrUpload.jinja' ))

    form = await fwrk.request.form
    txt = form.get("xmltext",default=None)

    #return ( True, (txt, 200, {'Content-Type': 'text/xml; charset=utf-8'}) )
    return ( True, add_respcode_by_reason( storage.postFunctionDef(txt) ))


#----------------------------------------------------------------------------

@app.route('/aac/function/upload/xmlfile', methods=["GET","POST"])
@aac_rq_handler
async def funcUpXmlFile():

    if fwrk.request.method == "GET":
        return (False, await fwrk.render_template( 'form4_xmlFileUpload.jinja'))

    files = await fwrk.request.files
    spooled_temp_file = files.get("xmlfile",default=None)
    if spooled_temp_file is None:
        logger.error(f"Required file field 'xmlfile' is not found in POST request body")
        return ( True, add_respcode_by_reason( {'result':False, 'reason':'WRONG-FORMAT'} ))

    txt = spooled_temp_file.read().decode('utf-8')

    #return ( True, (txt, 200, {'Content-Type': 'text/xml; charset=utf-8'}) )
    return ( True, add_respcode_by_reason( storage.postFunctionDef(txt) ))


#----------------------------------------------------------------------------

@app.route('/aac/funcsets')
@aac_rq_handler
async def funcsets():

    return ( True, {'result':True,'funcsets': storage.getFuncsets()} )

#----------------------------------------------------------------------------

@app.route('/aac/funcset/create', methods=["GET","POST"])
@aac_rq_handler
async def funcsetCreate():

    if fwrk.request.method == "GET":
        return (False, await fwrk.render_template( 'form4_branchFuncsetRdbl.jinja',
                                                   branchList = storage.listBranches(),                                                   
                                                 ))
    form = await fwrk.request.form
    branch,funcset,readable_name = (form.get(x,None) for x in ("branch","funcset","readablename"))

    return ( True, add_respcode_by_reason( storage.funcsetCreate(branch,funcset,readable_name) ))


#----------------------------------------------------------------------------

@app.route('/aac/funcset/delete', methods=["GET","POST"])
@aac_rq_handler
async def funcsetDelete():

    if fwrk.request.method == "GET":
        return (False, await fwrk.render_template( 'form4_funcset.jinja', formMethod="post",
                                                   funcSets = storage.getFuncsets(),
                                                 ))
    form = await fwrk.request.form
    funcset = form.get("funcset",None)

    return ( True, add_respcode_by_reason( storage.funcsetDelete(funcset) ))

#----------------------------------------------------------------------------

@app.route('/aac/funcset/details', methods=["GET"])
@aac_rq_handler
async def funcsetFuncs():

    funcset = fwrk.request.args.get("funcset",default=None)
    if funcset is None:
        return (False, await fwrk.render_template( 'form4_funcset.jinja', formMethod="get",
                                                   funcSets = storage.getFuncsets(),
                                                 ))
    return ( True, add_respcode_by_reason( storage.getFuncsetDetails(funcset) ))

#----------------------------------------------------------------------------

@app.route('/aac/funcset/function/add', methods=["GET","POST"])
@aac_rq_handler
async def funcsetFuncAdd():

    if fwrk.request.method == "GET":
        return (False, await fwrk.render_template( 'form4_funcsetFunc.jinja',
                                                   funcSets = storage.getFuncsets(),
                                                   funcList = storage.listFunctions("id")["values"],
                                                   funcRequired = True
                                                 ))
    form = await fwrk.request.form
    funcset = form.get("funcset",default=None)
    function_id = form.get("funcId",default=None)

    return ( True, add_respcode_by_reason( storage.funcsetFuncAdd(funcset,function_id) ))


#----------------------------------------------------------------------------

@app.route('/aac/funcset/function/remove', methods=["GET","POST"])
@aac_rq_handler
async def funcsetFuncRemove():

    form = await fwrk.request.form
    funcset = form.get("funcset",default="")
    function_id = form.get("funcId",default="")

    if fwrk.request.method == "GET" or funcset=="" or function_id=="":
        return (False, await fwrk.render_template( 'form4_funcsetFunc.jinja',
                                                   funcSets = storage.getFuncsets(),
                                                   funcSetInit = funcset,
                                                   funcList = storage.getFuncsetDetails(funcset)['functions'] if funcset!="" else (),
                                                   funcsetAutoSubmit = funcset=="",
                                                   funcRequired = funcset!=""
                                                 ))
    return ( True, add_respcode_by_reason( storage.funcsetFuncRemove(funcset,function_id) ))


#----------------------------------------------------------------------------

@app.route('/aac/role/funcsets', methods=["GET"])
@aac_rq_handler
async def roleFuncsets():

    branch,role = (fwrk.request.args.get(x,default="") for x in ("branch","role"))

    if any(p=="" for p in (branch,role)):
        return (False, await fwrk.render_template( 'form4_branchRole.jinja', formMethod="get",
                                                   branchList = storage.listBranches(),                                                   
                                                   branchInit = branch,
                                                   branchAutoSubmit = role=="",

                                                   rolesList = storage.listRoles4Branch(branch) if branch!="" else (),
                                                   roleRequired = branch!="",
                                                 ))
    return ( True, add_respcode_by_reason( storage.listRoleFuncsets(branch,role) ))

#----------------------------------------------------------------------------

@app.route('/aac/role/funcset/add', methods=["GET","POST"])
@aac_rq_handler
async def roleFuncsetAdd():

    form = await fwrk.request.form
    branch,role,funcset = (form.get(x,default="") for x in ("branch","role","funcset"))

    if fwrk.request.method == "GET" or any(p=="" for p in (branch,role,funcset)):
        return (False, await fwrk.render_template( 'form4_branchRoleFuncset.jinja',
                                                   branchList = storage.listBranches(),                                                   
                                                   branchInit = branch,
                                                   branchAutoSubmit = role=="",

                                                   rolesList = storage.listRoles4Branch(branch) if branch!="" else (),
                                                   roleRequired = branch!="",

                                                   funcSets = storage.getFuncsets(),
                                                 ))
    return ( True, add_respcode_by_reason( storage.roleFuncsetAdd(branch,role,funcset) ))

#----------------------------------------------------------------------------

@app.route('/aac/role/funcset/remove', methods=["GET","POST"])
@aac_rq_handler
async def roleFuncsetRemove():

    form = await fwrk.request.form
    branch,role,funcset = (form.get(x,default="") for x in ("branch","role","funcset"))

    if fwrk.request.method == "GET" or any(x=="" for x in (branch,role,funcset)):
        return (False, await fwrk.render_template( 'form4_branchRoleFuncset.jinja',

                                                   branchList = storage.listBranches(),                                                   
                                                   branchInit = branch,
                                                   branchAutoSubmit = role=="",

                                                   rolesList = storage.listRoles4Branch(branch) if branch!="" else (),
                                                   roleInit = role,
                                                   roleRequired = branch!="",
                                                   roleAutoSubmit = funcset=="",

                                                   funcSets = storage.listRoleFuncsets(branch,role)['funcsets'] if branch!="" and role!="" else (),
                                                   funcSetRequired = branch!="" and role!="",
                                                 ))
    return ( True, add_respcode_by_reason( storage.roleFuncsetRemove(branch,role,funcset) ))

#----------------------------------------------------------------------------

@app.route('/aac/branch/subbranches', methods=["GET"])
@aac_rq_handler
async def branchSubs():

    branch_id = fwrk.request.args.get("branch",default=None)
                                         
    if branch_id is None:
        return (False, await fwrk.render_template( 'form4_branch.jinja', formMethod="get",
                                                   branchList = storage.listBranches(),
                                                   branchCanBeEmpty = True,
                                                   label4Branch = "Parent branch (or leave empty for root)",                                                   
                                                 )
               )
    return ( True, add_respcode_by_reason( storage.getBranchSubs(branch_id) ))


#----------------------------------------------------------------------------

@app.route('/aac/branch/subbranch/add', methods=["GET","POST"])
@aac_rq_handler
async def branchSubAdd():

    form = await fwrk.request.form
    branch,subbranch = (form.get(x,default=None) for x in ("branch","subbranch"))

    if fwrk.request.method == "GET":
        return (False, await fwrk.render_template( 'form4_branch.jinja', formMethod="post",
                                                   branchList = storage.listBranches(),
                                                   label4Branch = "Parent branch",
                                                   subBranchRequired = True,
                                                 )
               )
    return ( True, add_respcode_by_reason( storage.addBranchSub(branch,subbranch) ))


#----------------------------------------------------------------------------

@app.route('/aac/branch/delete', methods=["GET","POST"])
@aac_rq_handler
async def branchDelete():

    form = await fwrk.request.form
    branch = form.get("branch",default=None)

    if fwrk.request.method == "GET":
        return (False, await fwrk.render_template( 'form4_branch.jinja', formMethod="post",
                                                   branchList = storage.listBranches(),
                                                 )
               )
    return ( True, add_respcode_by_reason( storage.deleteBranch(branch) ))


#----------------------------------------------------------------------------

@app.route('/aac/branch/fswhitelist/get', methods=["GET"])
@aac_rq_handler
async def branch_fswl_get():

    branch_id = fwrk.request.args.get("branch",default=None)
    if branch_id is None: 
        return (False, await fwrk.render_template( 'form4_branch.jinja', branchList = storage.listBranches() ))

    return (True, add_respcode_by_reason( storage.getBranchFsWhiteList(branch_id) ))



#----------------------------------------------------------------------------

@app.route('/aac/branch/fswhitelist/set', methods=["GET","POST"])
@aac_rq_handler
async def branch_fswl_set():

    if fwrk.request.method == "GET":
        branch = fwrk.request.args.get("branch",default="")
        init = {} if branch=="" else storage.getBranchFsWhiteList(branch)
        return (False, await fwrk.render_template( 'form4_branchWList.jinja', 
                                                   branchList = storage.listBranches(),
                                                   branchInit = branch,
                                                   branchAutoSubmit = branch=="",
                                                   funcSets = storage.getFuncsets(),
                                                   init = init,
                                                 )
               )

    form = await fwrk.request.form
    branch = form.get("branch",default=None)
    propParent = form.get("propparent",default="no")
    wl = form.getlist("white")
    return (True, add_respcode_by_reason( storage.setBranchFsWhiteList(branch, propParent=='yes', wl) ))


#----------------------------------------------------------------------------

@app.route('/aac/branch/roles/list', methods=["GET"])
@aac_rq_handler
async def branch_roles_list():               

    branch_id = fwrk.request.args.get("branch",default=None)
    inherited,withbrids = (fwrk.request.args.get(x,default="no") for x in ("inherited","withbranchids"))

    if branch_id is None: 
        return (False, await fwrk.render_template( 'form4_branchExt.jinja' , 
                                                   branchList = storage.listBranches(),
                                                   cboxes=( ("inherited","Include inherited roles"),
                                                            ("withbranchids","Report also branch IDs"),
                                                          )
                                                 ))
    return (True, add_respcode_by_reason( storage.listBranchRoles(branch_id, inherited=='yes', withbrids=='yes')))


#----------------------------------------------------------------------------

@app.route('/aac/branch/role/delete', methods=["GET","POST"])
@aac_rq_handler
async def branchRoleDelete():

    form = await fwrk.request.form
    branch,role = (form.get(x,default="") for x in ("branch","role"))

    if any(p=="" for p in (branch,role)):
        return (False, await fwrk.render_template( 'form4_branchRole.jinja', formMethod="post",
                                                   branchList = storage.listBranches(),                                                   
                                                   branchInit = branch,
                                                   branchAutoSubmit = role=="",

                                                   rolesList = storage.listRoles4Branch(branch) if branch!="" else (),
                                                   roleRequired = branch!="",
                                                 ))
    return ( True, add_respcode_by_reason( storage.deleteBranchRole(branch,role) ))

#----------------------------------------------------------------------------

@app.route('/aac/branch/role/create', methods=["GET","POST"])
@aac_rq_handler
async def branchRoleCreate():

    form = await fwrk.request.form
    branch,role = (form.get(x,default="") for x in ("branch","role"))
    duties = form.getlist("duties")

    if any(p=="" for p in (branch,role)):
        return (False, await fwrk.render_template( 'form4_branchRoleInit.jinja', formMethod="post",
                                                   branchList = storage.listBranches(),                                                   
                                                   branchInit = branch,
                                                   branchAutoSubmit = branch=="",

                                                   roleRequired = branch!="",

                                                   funcSets = storage.getFuncsets(),
                                                   enabledFuncSets = storage.getBranchEnabledFuncsets(branch) if branch!="" else (),
                                                 ))
    return ( True, add_respcode_by_reason( storage.createBranchRole(branch,role,duties) ))

#----------------------------------------------------------------------------

@app.route('/aac/agent/register', methods=["GET","POST"])
@aac_rq_handler
async def agentRegister():

    form = await fwrk.request.form
    branch,agent,descr,location,tags,extraxml = (form.get(x,"") for x in ("branch","agent","descr","location","tags","extraxml"))
    
    #logger.info(f"Branch is {repr(branch)}")
    #for a in form.keys():
    #   logger.info(f"- {repr(a)} : {repr(form[a])}")

    if fwrk.request.method == "GET":
        return (False, await fwrk.render_template( 'form4_agentBranchRegInfo.jinja', formMethod="post",
                                                   branchList = ["*ROOT*"] + storage.listBranches(),
                                                   extratxtinputs = ( ("descr","Description",""),
                                                                      ("location","Location",""),
                                                                      ("tags","Tags (comma separated)",""),
                                                                      ("extraxml","Optional info in free XML format",""),
                                                                    )
                                                 ))
    return ( True, add_respcode_by_reason( storage.registerAgentInBranch( branch,agent,move=False,
                                                                          descr=descr,location=location,tags=tags,extraxml=extraxml
                                                                        ) ))

#----------------------------------------------------------------------------

@app.route('/aac/agent/movedown', methods=["GET","POST"])
@aac_rq_handler
async def agentMoveDown():

    form = await fwrk.request.form
    branch,agent,descr,location,tags,extraxml = (form.get(x,"") for x in ("branch","agent","descr","location","tags","extraxml"))

    if any(p=="" for p in (branch,agent)):

        ini = {'descr':'','extra':'','location':'','tags':''}
        if agent!="":
            agdet = storage.agentDetailsJson(agent)
            if agdet['result']:
                ini = agdet['details']

        return (False, await fwrk.render_template( 'form4_agentBranchRegInfo.jinja', formMethod="post",
                                                   agentsList = sorted(storage.getAgents()),
                                                   agentInit = agent,
                                                   agentAutoSubmit = branch=="",
                                                   branchList = () if agent=="" else storage.getSubBranchesOfAgent(agent),
                                                   extratxtinputs = ( ("descr","Description",ini['descr']),
                                                                      ("location","Location",ini['location']),
                                                                      ("tags","Tags (comma separated)",ini['tags']),
                                                                      ("extraxml","Optional info in free XML format",ini['extra']),
                                                                    )
                                                 ))

    return ( True, add_respcode_by_reason( storage.registerAgentInBranch( branch,agent,move=True,
                                                                          descr=descr,location=location,tags=tags,extraxml=extraxml
                                                                        ) ))

#----------------------------------------------------------------------------

@app.route('/aac/agent/unregister', methods=["GET","POST"])
@aac_rq_handler
async def agentUnregister():

    form = await fwrk.request.form
    agent = form.get("agent",default="")

    if fwrk.request.method == "GET":
        return (False, await fwrk.render_template( 'form4_agent.jinja', formMethod="post",
                                                   agentsList = sorted(storage.getAgents()),                                                   
                                                 ))
    return ( True, add_respcode_by_reason( storage.unregisterAgent(agent) ))

#----------------------------------------------------------------------------

@app.route('/aac/agent/details/xml', methods=["GET"])
@aac_rq_handler
async def agentDetailsXml():

    agent = fwrk.request.args.get("agent",default=None)

    if agent is None:
        return (False, await fwrk.render_template( 'form4_agent.jinja', formMethod="get",
                                                   agentsList = sorted(storage.getAgents()),                                                   
                                                 ))
    preret = storage.agentDetailsXml(agent)
    if not preret["result"]:
        return ( True, add_respcode_by_reason( preret ))
    else:
        return ( True, (preret["details"], 200, {'Content-Type': 'text/xml; charset=utf-8'}) )

#----------------------------------------------------------------------------

@app.route('/aac/agent/details/json', methods=["GET"])
@aac_rq_handler
async def agentDetailsJson():

    agent = fwrk.request.args.get("agent",default=None)

    if agent is None:
        return (False, await fwrk.render_template( 'form4_agent.jinja', formMethod="get",
                                                   agentsList = sorted(storage.getAgents()),                                                   
                                                 ))
    return ( True, add_respcode_by_reason( storage.agentDetailsJson(agent) ))

#----------------------------------------------------------------------------

@app.route('/aac/agents/list', methods=["GET"])
@aac_rq_handler
async def listAgents():

    branch_id = fwrk.request.args.get("branch",default=None)
    withSubs,withLoc = (fwrk.request.args.get(x,default="no") for x in ("subsidinaries","location"))

    if branch_id is None: 
        return (False, await fwrk.render_template( 'form4_branchExt.jinja' , 
                                                   branchList = ["*ALL*"] + storage.listBranches(),
                                                   cboxes=( ("subsidinaries","Including subsidinaries"),
                                                            ("location","With location branch"),
                                                          )
                                                 ))
    else:
        return (True, add_respcode_by_reason( storage.listAgents(branch_id,withSubs=='yes',withLoc=='yes') ))


#----------------------------------------------------------------------------

@app.route('/aac/function/tagset/modify', methods=["GET","POST"])
@aac_rq_handler
async def tagsetModify():

    form = await fwrk.request.form
    funcId,method = (form.get(x,default=None) for x in ("funcId","method"))
    tagset = set(filter(len,form.getlist("tag")))

    if fwrk.request.method == "GET":
        return (False, await fwrk.render_template( 'form4_funcTagsetOps.jinja', formMethod="post",
                                                   funcRequired = True, 
                                                   funcList = storage.listFunctions("id")["values"],
                                                 ))
    return ( True, add_respcode_by_reason( storage.modifyFuncTagset(funcId,method,tagset) ))

#----------------------------------------------------------------------------

@app.route('/aac/function/tagset/test', methods=["GET"])
@aac_rq_handler
async def tagsetTest():

    funcId,method = (fwrk.request.args.get(x,default=None) for x in ("funcId","method"))
    tagset = set(filter(len,fwrk.request.args.getlist("tag")))                                 

    if any(x is None or x=="" for x in (funcId,method)):
        return (False, await fwrk.render_template( 'form4_funcTagsetOps.jinja', formMethod="get",
                                                   funcRequired = True, 
                                                   funcList = storage.listFunctions("id")["values"],
                                                   readOnly = True,
                                                 ))
    return ( True, add_respcode_by_reason( storage.modifyFuncTagset(funcId,method,tagset,read_only=True) ))

#----------------------------------------------------------------------------

@app.route('/aac/testrunner/states', methods=["GET"])
@aac_rq_handler
async def testrunnerStates():

    taskId = fwrk.request.args.get("poll",default="")
    if len(taskId):
        return ( True, await testRunner.testTask.checkTask(taskId) )
    else:
        durEach = fwrk.request.args.get("durationEach",default="")
        states = fwrk.request.args.get("states",default="")
        finMess = fwrk.request.args.get("final",default="")
        agent = fwrk.request.args.get("agent",default="")

        statesA = states.split(",")
        taskid = await testRunner.testTask.runTestGeneric( statesA, [int(durEach)]*len(statesA), {'final_message':finMess, 'agent_id':agent} )
        await asyncio.sleep(1)
        return ( True, await testRunner.testTask.checkTask(taskid) )

#----------------------------------------------------------------------------
@app.route('/aac/branches', methods=["GET"])
@aac_rq_handler
async def get_branches():

    return (True, add_respcode_by_reason({'result': True, 'data':storage.getBranches("")}))

#----------------------------------------------------------------------------

@app.route('/aac/positions', methods=["GET"])
@aac_rq_handler
async def get_positions():
    branch = fwrk.request.args.get("filter", default="")
    return (True, add_respcode_by_reason({'result': True, 'data':storage.getPositions(branch)}))

#----------------------------------------------------------------------------

def adjustLogging(filename):

    with open(filename, 'r', encoding='utf-8-sig') as cfgStream: # can eat both BOM and non-BOM utf-8 files with this -sig suffix
        try:
            cfgDict = yaml.safe_load(cfgStream)
            print('Starting with logger configuration:\n'+ repr(cfgDict))
            logging.config.dictConfig(cfgDict)
            #logger.info('Starting with logger configuration:\n'+ repr(cfgDict))
        except Exception:
            print('Logger configuration failure',file=sys.stderr)
            raise



#----------------------------------------------------------------------------

@app.after_request
def after_request(response):
   
    #logger.debug(f"!@#$$$ Request headers are {repr(fwrk.request.headers)}")
    origin = fwrk.request.headers.get('Origin',None)
    logger.info(f"Post-processing response to request from origin {repr(origin)}")

    if origin is None:
        logger.info(f"Doing none with request from None origin")
    else:
        global _aac_cors_whitelist
        if origin in _aac_cors_whitelist:
            logger.info(f"Welcomed request from whitelisted origin {repr(origin)}!")
            logger.debug(f"Initially response headers were {repr(response.headers)}")

            response.headers['Access-Control-Allow-Origin'] = fwrk.request.headers['Origin'] 
            #response.headers['Access-Control-Allow-Methods'] = '*'

            logger.debug(f"And now response headers are {repr(response.headers)}")
        else:
            logger.info(f"Request from a non-whitelisted origin {repr(origin)} - leaving headers as is")

    return response

#----------------------------------------------------------------------------

async def main():

    adjustLogging("config/logging.yaml")
    logger.info('aac started')

    with open("config/general.yaml", 'r', encoding='utf-8-sig') as cfgStream: # can eat both BOM and non-BOM utf-8 files with this -sig suffix
        try:
            global cfgDict
            cfgDict = yaml.safe_load(cfgStream)
            logger.info('Configuration dictionary:\n'+ repr(cfgDict))
        except Exception:
            logger.exception('General config problem')
            raise

    runAt=next(filter(lambda x: x.startswith("-runat="),sys.argv), "-runat="+cfgDict["default_run_location"] ).partition("=")[2]
    logger.info('Running at ' + runAt)

    global storage
    storage = configDataKeeper(
        "DATA",
        cfgDict["session_max_default"]
    )
    storage.load()

    # configuring some globals in storage provided by framework:
    global _aac_cors_whitelist
    _aac_cors_whitelist = set(cfgDict["run_locations"][runAt].get('cors_whitelist',[]))
    logger.info(f'CORS whitelist is {_aac_cors_whitelist}')


    # and running server:
    await app.run_task(
        host='0.0.0.0',
        port= cfgDict["run_locations"][runAt]["port"],
        debug=cfgDict.get("debug", False),
        )

    logger.info('aac exited')

#----------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(main())

#----------------------------------------------------------------------------
