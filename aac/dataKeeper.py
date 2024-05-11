import sys
import json
from lxml import etree
import os
import time
import re
from agentsKeeper import agentsDataKeeper

#--------------------------------------------------------------------------------------------------------------

_logName = "dataKeeper"
import logging
logger = logging.getLogger(_logName)

#--------------------------------------------------------------------------------------------------------------

class configDataKeeper:

    #-------------
    def __init__(self, data_catalogue, default_sess_max):

        self._filename = data_catalogue + "/universe.xml"
        self._cFilename = data_catalogue + "/catalogues.xml"

        self._parser = etree.XMLParser( remove_blank_text=True )
        self._dflt_sess_max = default_sess_max

        self._agents_keeper = agentsDataKeeper(data_catalogue)

    #-------------
    def load(self):
        self._xmlstorage = etree.parse( self._filename, self._parser )
        logger.info(f"Data for Config Data Keeper loaded from {self._filename}") 
        logger.debug(f"Data tree is:\n" + etree.tostring(self._xmlstorage, pretty_print=True, encoding='unicode' )) 

        self._xmlcats = self._getCatalogues()

        self._agents_keeper.init_data()


    #-------------
    def _getCatalogues(self):
        ret = etree.parse( self._cFilename, self._parser )
        logger.info(f"Data for Catalogues loaded from {self._cFilename}") 
        #logger.debug(f"Data tree is:\n" + etree.tostring(ret, pretty_print=True, encoding='unicode' )) 
        return ret

    #-------------
    def _save(self, catalogues=False):

        baseFName = self._cFilename if catalogues else self._filename
        tempFilename,bkFilename = (baseFName+sfx for sfx in (".temp.xml",".bk.xml"))

        textdump = etree.tostring(self._xmlcats if catalogues else self._xmlstorage, pretty_print=True, encoding='unicode' )

        with open(tempFilename,"w", encoding='utf-8-sig') as f:
            f.write(textdump)
        logger.debug(f"Database successfully dumped to {tempFilename}")

        if os.path.exists(bkFilename):
            os.remove(bkFilename)
        os.rename(baseFName, bkFilename)
        os.rename(tempFilename, baseFName)

        logger.info(f"Castling made, old data is in {bkFilename}, new one in {baseFName}") 
        

    #-------------
    def _getUserNode(self,userid):
        logger.debug(f"Searching record for user '{userid}'")
        unodes = etree.XPath(f"/universe/registers/people_register/person[@id='{userid}']")(self._xmlstorage)
        return None if len(unodes)==0 else unodes[0]

    #-------------
    def _procFailure(self,unode, failures, warntext):
        logger.warning(warntext)
        unode.set( 'failures', str(failures) )
        unode.set( 'last_error', str(int(time.time())) )
        self._save()

    #-------------
    def _reviewFunc4thePage(self,fi):
        ret = self.reviewFunctions("id,name,title",fi)
        return ret["props"] if ret['result'] else {"id":fi,"name":"UNDESCRIBED "+fi,"title":"UNDESCRIBED "+fi}

    #-------------

    def _add_app_details(self,ret,app_name,userid):
        ret['for_application'] = app_name

        if app_name == "gAP":
            ret['branches'] = self.userBranches(userid)
            ret['positions'] = self.userPositions(userid)
            ret['func_groups'] = self._userFuncSets(userid)
            ret['functions'] = [ self.reviewFunctions("id,callpath,method",fi)["props"] for fi in self.__empFunctionIds(userid) ]
            ret['agents'] = [] if len(ret['branches'])==0 else self.listAgents(ret['branches'][0],True,False)['report']

        elif app_name == "thePage":
            ret['funcsets'] = { fsDet['id']: { "name": fsDet['name'],
                                               "functions": [ self._reviewFunc4thePage(fi) for fi in fsDet['functions'] ] 
                                             } for fsDet in ( self.getFuncsetDetails(fsId) for fsId in self._userFuncSets(userid) )
                              }
        return ret

    #-------------
    def get_user_reg_details(self,userid,app_name=None):

        if userid is None:
            return configDataKeeper._internEx( "WRONG-FORMAT", f"Not all required parameters are given: user id {repr(userid)}" ).dict4api

        unode = self._getUserNode(userid)
        if unode is None:
            return configDataKeeper._internEx( "USER-UNKNOWN", f"User '{userid}' is unknown" ).dict4api

        ret = { 'result': True, 
                 'secret_changed': int(unode.get('pswChangedAt')),
                 'secret_expiration': int(unode.get('expireAt')) if "expireAt" in unode.attrib else 0,
                 'readable_name' : unode.get('readableName',""),
                 'session_max' : int(unode.get('sessionMax', self._dflt_sess_max)),
                 'created' : [unode.get('createdBy',""),unode.get('createdAt',"")],
                 'change_history': [ [x.get('by'),x.get('at')] for x in etree.XPath("changed")(unode) ]
              }
        if not app_name in (None, ""):
            self._add_app_details(ret,app_name,userid)
        logger.info(f"User '{userid}' reg data prepared: {ret}")
        return ret
                
    #-------------
    def authorize(self,userid,secret,app_name):

        if secret is None:
            return configDataKeeper._internEx( "WRONG-FORMAT", f"Not all required parameters are given: secret is {repr(secret)}" ).dict4api

        ret = self.get_user_reg_details(userid,app_name)
        if ret['result']:
            unode = self._getUserNode(userid)
            failures = int(unode.get('failures',0))
            if secret != unode.get('secret'):
                failures += 1
                self._procFailure(unode, failures, f"User '{userid}' made {failures} password mistake(s)")
                return { 'result': False, 'reason':'WRONG-SECRET', 'failures':failures }

            expiretime = int(unode.get('expireAt')) if "expireAt" in unode.attrib else 0
            currtime = int(time.time())
            if expiretime and currtime > expiretime:
                failures += 1
                self._procFailure(unode, failures, f"Password of '{userid}' expired at {time.ctime(expiretime)}, failures counter is {failures}")
                return { 'result': False, 'reason':'SECRET-EXPIRED','secret_expiration': expiretime, 'failures':failures }

            logger.info(f"User '{userid}' authentificated")
            unode.set( 'failures', "0" )
            unode.set( 'last_auth_success', str(currtime) )
            self._save()

        return ret
                
    #-------------
    def getFuncsets(self):
        fsIds = etree.XPath("//branch/deffuncsets/funcset/@id")(self._xmlstorage)
        return fsIds
 
    #-------------

    def funcsetCreate(self,branch_id,funcset_id,readable_name):
        try:
            defFsNode = self._getBranchNodeS(branch_id,subpath='deffuncsets')
        except configDataKeeper._internEx as ex:
            return ex.dict4api

        if funcset_id is None or funcset_id=="":
            return configDataKeeper._internEx( 'WRONG-FORMAT', f"Required argument not given: funcset is {repr(funcset_id)}" ).dict4api

        if len(etree.XPath(f'//branch/deffuncsets/funcset[@id="{funcset_id}"]')(self._xmlstorage)):
            return configDataKeeper._internEx( "ALREADY-EXISTS", f"Funcset {repr(funcset_id)} already defined somewhere", bad_value=funcset_id ).dict4api

        fsnode = etree.SubElement(defFsNode, "funcset")
        fsnode.set("id",funcset_id)
        if not readable_name in (None, ""):
            fsnode.set("name",readable_name)
        self._save()
        return { 'result': True }

    #-------------

    def funcsetDelete(self,funcset_id):
        try:
            fsNode = self._getFsNode(funcset_id)
        except configDataKeeper._internEx as ex:
            return ex.dict4api

        fsNode.getparent().remove(fsNode)
        self._save()
        return { 'result': True }

    #-------------
    def _getFsNode(self,funcset_id,**kwargs):

        if funcset_id is None or funcset_id=="":
            raise configDataKeeper._internEx( 'WRONG-FORMAT', "Required funcset id is not given" )

        if 'func' in kwargs and (kwargs['func'] is None or kwargs['func']==""):
            raise configDataKeeper._internEx( 'WRONG-FORMAT', "Required function name is not given" )

        fsNodes = etree.XPath(f'//branch/deffuncsets/funcset[@id="{funcset_id}"]')(self._xmlstorage)
        if len(fsNodes)==0:
            raise configDataKeeper._internEx( 'FUNCSET-UNKNOWN', f"Funcset {repr(funcset_id)} is unknown", bad_value=funcset_id )

        return fsNodes[0]
 
    #-------------
    def getFuncsetDetails(self,funcset_id):
        try:
            fsNode = self._getFsNode(funcset_id)
        except configDataKeeper._internEx as ex:
            return ex.dict4api

        funcIds = etree.XPath(f"func/@id")(fsNode)
        return { 'result': True, 'functions': funcIds, 'name': fsNode.get('name',''), 'id':funcset_id }
 
    #-------------
    def funcsetFuncAdd(self,funcset_id,funcId):
        try:
            fsNode = self._getFsNode(funcset_id, func=funcId)
        except configDataKeeper._internEx as ex:
            return ex.dict4api

        if len(etree.XPath(f'func[@id="{funcId}"]')(fsNode)):
            return configDataKeeper._internEx( "ALREADY-EXISTS", f"Function {repr(funcId)} already in {repr(funcset_id)}", bad_value=funcId ).dict4api

        etree.SubElement(fsNode, "func").set("id",funcId)
        self._save()
        return { 'result': True }

    #-------------
    def funcsetFuncRemove(self,funcset_id,funcId):
        try:
            fsNode = self._getFsNode(funcset_id, func=funcId)
        except configDataKeeper._internEx as ex:
            return ex.dict4api

        funcNodes = etree.XPath(f'func[@id="{funcId}"]')(fsNode)
        if len(funcNodes)==0:
            return configDataKeeper._internEx( "NOT-IN-SET", f"Function {repr(funcId)} is not in {repr(funcset_id)}", bad_value=funcId ).dict4api

        fsNode.remove(funcNodes[0])
        self._save()
        return { 'result': True }
 
    #-------------
    def userBranches(self,userid):
        brIds = etree.XPath(f"//branch[employees/employee/@person='{userid}']/@id")(self._xmlstorage)
        logger.info(f"Branches for user '{userid}' are {repr(brIds)}")
        return brIds
 
    #-------------
    def userPositions(self,userid):
        poses = etree.XPath(f"//employee[@person='{userid}']/@pos")(self._xmlstorage)
        logger.info(f"Positions for user '{userid}' are {repr(poses)}")
        return poses
 
    #-------------
    def listBranches(self):
        brIds = etree.XPath(f"//branch/@id")(self._xmlstorage)
        logger.debug(f"Branches are {repr(brIds)}")
        return brIds
 
    #-------------
    def listRoles4Branch(self,branch_id):
        roleNames = etree.XPath(f"//branch[@id='{branch_id}']/roles/role/@name")(self._xmlstorage)
        logger.info(f"Roles defined in branch {repr(branch_id)} are {repr(roleNames)}")
        return roleNames
 
    #-------------

    def _getRoleNode(self,branch_id,role_name):
        rolesnode = self._getBranchNodeS(branch_id,subpath='roles')

        if role_name is None or role_name=="":
            raise configDataKeeper._internEx( 'WRONG-FORMAT', f"Required argument not given: role is {repr(role_name)}" )

        roleNodes = etree.XPath(f"role[@name='{role_name}']")(rolesnode)
        if len(roleNodes)==0:
            raise configDataKeeper._internEx( "ROLE-UNKNOWN", f"Role {role_name} not defined in branch {branch_id}" )
        return roleNodes[0]

    #-------------

    def listRoleFuncsets(self,branch_id,role_name):
        try:
            roleNode = self._getRoleNode(branch_id,role_name)
        except configDataKeeper._internEx as ex:
            return ex.dict4api

        return { 'result':True, 'funcsets': etree.XPath("funcset/@id")(roleNode)}
 
    #-------------

    def roleFuncsetAdd(self,branch_id,role_name,funcset_id):
        try:
            roleNode = self._getRoleNode(branch_id,role_name)
        except configDataKeeper._internEx as ex:
            return ex.dict4api

        if len(etree.XPath(f"funcset[@id='{funcset_id}']")(roleNode)):
            return configDataKeeper._internEx( "ALREADY-EXISTS", 
                                               f"Funcset {repr(funcset_id)} already in role {repr(role_name)} of {repr(branch_id)}" ).dict4api

        etree.SubElement(roleNode, "funcset").set("id",funcset_id)
        self._save()
        return { 'result': True }
 
    #-------------

    def roleFuncsetRemove(self,branch_id,role_name,funcset_id):
        try:
            roleNode = self._getRoleNode(branch_id,role_name)
        except configDataKeeper._internEx as ex:
            return ex.dict4api

        fsNodes = etree.XPath(f"funcset[@id='{funcset_id}']")(roleNode)
        if len(fsNodes)==0:
            return configDataKeeper._internEx( "NOT-IN-SET", 
                                               f"Funcset {repr(funcset_id)} is not in role {repe(role_name)} of {repr(branch_id)}" ).dict4api

        roleNode.remove(fsNodes[0])
        self._save()
        return { 'result': True }
 
    #-------------

    def reviewBranches(self,pos=""):
        spec1= "" if pos=="" else f"[employees/employee/@pos='{pos}']"
        spec2= "" if pos=="" else f" and @pos='{pos}'"
        brs = etree.XPath(f"//branch{spec1}")(self._xmlstorage)
        ret = [ { 'id': n.get("id"),
                  'vacancies': list(etree.XPath(f"employees/employee[not(@person){spec2}]/@pos")(n)),
                } for n in brs ]
        logger.info(f"Branches review is {ret}")
        return ret
 
    #-------------
    def getBranches(self,pos=""):
        spec1= "" if pos=="" else f"[employees/employee/@pos='{pos}']"
        spec2= "" if pos=="" else f" and @pos='{pos}'"
        brs = etree.XPath(f"//branch{spec1}")(self._xmlstorage)
        ret = [ { 'id': n.get("id"),
                  'value': f'{n.get("id")} - {len(list(etree.XPath(f"employees/employee[not(@person){spec2}]/@pos")(n)))} vacancies',
                } for n in brs ]
        logger.info(f"Branches review is {ret}")
        return ret
 
    #-------------
    
    def getBranchSubs(self,branch_id):
        if branch_id=="":
            root=self._xmlstorage
        else:
            try:
                root = self._getBranchNodeS(branch_id)
            except configDataKeeper._internEx as ex:
                return ex.dict4api
 
        brIds = etree.XPath(f"descendant::branch/@id")(root)
        logger.debug(f"Branches descendant to {repr(branch_id)} are {repr(brIds)}")
        return {'result': True, 'branches': sorted(brIds) }
 
    #-------------
    def addBranchSub(self,branch_id,sub_id):
        try:
            sbrsNode = self._getBranchNodeS(branch_id,subpath='branches')
        except configDataKeeper._internEx as ex:
            return ex.dict4api

        if sub_id is None or sub_id=="":
            return configDataKeeper._internEx('WRONG-FORMAT',f"Required argument not given: subbranch is {repr(sub_id)}").dict4api

        if len(etree.XPath(f"branch[@id='{sub_id}']")(sbrsNode)):
            return configDataKeeper._internEx( 'ALREADY-EXISTS', f"Branch {repr(branch_id)} already has subbranch {repr(sub_id)}", bad_value=sub_id ).dict4api

        sbrsNode.append( etree.fromstring( '''
            <branch id="%s">
                <func_white_list propagateParent="no"/>
                <employees/>
                <roles/>
                <deffuncsets/>
                <branches/>
            </branch>
            ''' % ( sub_id ), self._parser ))

        self._save()
        return {'result': True }
 
    #-------------
    def deleteBranch(self,branch_id):
        try:
            branchNode = self._getBranchNodeS(branch_id)
        except configDataKeeper._internEx as ex:
            return ex.dict4api

        if len(etree.XPath("ancestor::branch")(branchNode))==0:
            return configDataKeeper._internEx( 'NOT-ALLOWED', f"Deletion of a root branch {repr(branch_id)} is not allowed", bad_value=branch_id ).dict4api
          
        emps = etree.XPath(f"descendant::employee/@person")(branchNode)
        if len(emps):
            return configDataKeeper._internEx( 'USER-EMPLOYED', f"Branch {repr(branch_id)} still has employees: {emps}", fire_them=emps ).dict4api

        branchNode.getparent().remove( branchNode )
        self._save()

        return {'result': True }
 
    #-------------
    def getBranchFsWhiteList(self,branch_id):
        try:
            wlNode = self._getBranchNodeS(branch_id,subpath='func_white_list')
        except configDataKeeper._internEx as ex:
            return ex.dict4api
 
        return { 'result': True, 
                 'funcsets': sorted( etree.XPath("funcset/@id")(wlNode) ),
                 'propagate_parent_flag': wlNode.get('propagateParent','no')=='yes',
               }
 
    #-------------
    def setBranchFsWhiteList(self,branch_id,prop_parent_flag,newwlist):
        try:
            wlNode = self._getBranchNodeS(branch_id,subpath='func_white_list')
        except configDataKeeper._internEx as ex:
            return ex.dict4api
 
        wlNode.set('propagateParent', 'yes' if prop_parent_flag else 'no')

        for fsn in etree.XPath("funcset")(wlNode):
            wlNode.remove(fsn)
        for fs in newwlist:
            etree.SubElement(wlNode, "funcset").set("id",fs)

        self._save()
        return { 'result': True  }
 
    #-------------

    def _getBranchNodeS(self,branch_id, subpath=None, autocreate=False):
        if branch_id is None or branch_id=="":            raise configDataKeeper._internEx('WRONG-FORMAT',f"Required argument not given: branch is {repr(branch_id)}")
        brs=etree.XPath(f"//branch[@id='{branch_id}']")(self._xmlstorage)
        if len(brs)==0:
            raise configDataKeeper._internEx( 'BRANCH-UNKNOWN', f"Branch {repr(branch_id)} is unknown", bad_value=branch_id )
        if subpath is None:
           return brs[0]
        subs=etree.XPath(subpath)(brs[0])
        if len(subs)==0:
            if not autocreate:
                raise configDataKeeper._internEx( 'DATABASE-ERROR', f"Inconsistent server data: branch {repr(branch_id)} description has no sub-path {repr(subpath)}", inconsistence=subpath )
            return etree.SubElement(brs[0],subpath)
        return subs[0]
 
    #-------------
    def listUsers(self):
        pIds = etree.XPath(f"/universe/registers/people_register/person/@id")(self._xmlstorage)
        logger.debug(f"People are {repr(pIds)}")
        return { 'result': True,
                 'users': pIds,
               }
 
    #-------------
    def reviewPositions( self, branchId="" ):
        spec= "" if branchId=="" else f"[@id='{branchId}']"
        eNodes = etree.XPath(f"//branch{spec}/employees/employee")(self._xmlstorage)
        ret = [ { 'pos':n.get("pos"),
                  'branch':n.getparent().getparent().get("id"),
                  'vacant': not "person" in n.attrib
                } for n in eNodes ]
        logger.info(f"Positions review is {ret}")
        return ret

    #-------------
    
    def getPositions( self, branchId="" ):
        spec= "" if branchId=="" else f"[@id='{branchId}']"
        eNodes = etree.XPath(f"//branch{spec}/employees/employee")(self._xmlstorage)
        ret = [ { 'id':n.get("pos"),
                  'value':f"{n.get('pos')} at {n.getparent().getparent().get('id')} {'VACANT' if not 'person' in n.attrib else 'OCCUPIED'}",
                } for n in eNodes ]
        logger.info(f"Positions review is {ret}")
        return ret

    #-------------

    def get_branches_with_positions( self, branch_id, per_role, only_vacant ):

        specB= '' if branch_id=='*ALL*' else f'[@id="{branch_id}"]'
        specV= 'not(@person)' if only_vacant else 'true()'
        br_nodes = etree.XPath(f'//branch{specB}/employees/employee[{specV}]/../..')(self._xmlstorage)

        if not per_role:
            rep =( { 'branch':b.get('id',None), 
                     'count': int(etree.XPath(f'count(employees/employee[{specV}])') (b) ),
                   } for b in br_nodes )
        else:
            rep = (  { 'branch':b.get('id',None), 
                       'role':p, 
                       'count': int(etree.XPath(f'count(employees/employee[@pos="{p}" and {specV}])')(b)),
                     }  for b in br_nodes for p in set(etree.XPath(f'employees/employee[{specV}]/@pos')(b))
                  )

        return { 'result': True, 
                 'branch_filter': branch_id, 
                 'only_vacant': only_vacant,
                 'report': list(rep)
               }

    #-------------
    def _collectBranchFuncsets( self, branchNode ):

        branch_id = branchNode.get('id')
        if branch_id is None: # not a branch
            logger.info(f"_collectBranchFuncsets - non-branch node achieved")
            return set()

        defined_here = set( etree.XPath("deffuncsets/funcset/@id")(branchNode) )
        logger.info(f"_collectBranchFuncsets for {repr(branch_id)}: Funcsets defined locally: {defined_here}")

        wlNodes = etree.XPath("func_white_list")(branchNode)
        ancBranches = etree.XPath("ancestor::branch")(branchNode)
        if len(wlNodes)==0 or len(ancBranches)==0: 
            logger.info(f"_collectBranchFuncsets for {repr(branch_id)}: Nothing to take from parent")
            return defined_here

        parent_funcsets = self._collectBranchFuncsets(ancBranches[-1])

        if wlNodes[0].get("propagateParent","no")=="yes":
            logger.info(f"_collectBranchFuncsets for {repr(branch_id)}: - Propagating parent funcsets {parent_funcsets} as is")
            ret = defined_here | parent_funcsets
        else:
            wl = set( etree.XPath("funcset/@id")(wlNodes[0]) )
            logger.info(f"_collectBranchFuncsets for {repr(branch_id)}: - Intersecting parent funcsets {parent_funcsets} with whitelist {wl}")
            ret = defined_here | (parent_funcsets & wl)

        logger.info(f"_collectBranchFuncsets for {repr(branch_id)}: - final result is {ret}")
        return ret

    #-------------
    def _findRoleNode( self, pos, branchNode ):
        logger.debug(f"Searching for role definition for pos '{pos}' starting from branch {branchNode.get('id')}")          
        roleNodes = etree.XPath(f"ancestor-or-self::branch/roles/role[@name='{pos}']")(branchNode)
        logger.debug(f"Found {len(roleNodes)} role definitions for '{pos}' among ancestors of '{branchNode.get('id')}'")
        if len(roleNodes)==0:
            return None
        else:
            # taking the last element to get the closest to our node definiton, because XPath returns info in "documented" order
            logger.info(f"Taking definition for {repr(pos)} from {repr(roleNodes[-1].getparent().getparent().get('id'))} (closest of {len(roleNodes)} to {repr(branchNode.get('id'))})")
            return roleNodes[-1]
         

    #-------------
    def listEnabledRoles4Branch( self, branch_id ):
        try:
            branch_node = self._getBranchNodeS(branch_id)
        except configDataKeeper._internEx as ex:
            return []
        return sorted( set( etree.XPath(f"ancestor-or-self::branch/roles/role/@name")(branch_node) ))

    #-------------
    def createBranchPosition( self, branch, role ):
        try:
            empsNode = self._getBranchNodeS(branch,"employees")
        except configDataKeeper._internEx as ex:
            return ex.dict4api
       
        etree.SubElement(empsNode,"employee").set("pos", role)
        self._save()

        return { 'result': True,
                 'branch' : branch,
                 'pos' : role,
                 'total': int( etree.XPath(f"count(employee[@pos='{role}'])")(empsNode) ),
                 'vacant': int( etree.XPath(f"count(employee[@pos='{role}' and not(@person)])")(empsNode) ),
               }

    #-------------
    def deleteBranchPosition( self, branch, role ):
        try:
            empsNode = self._getBranchNodeS(branch,"employees")
        except configDataKeeper._internEx as ex:
            return ex.dict4api
   
        posNodes = etree.XPath(f"employee[@pos='{role}' and not(@person)]")(empsNode)
        if len(posNodes)==0:
            return configDataKeeper._internEx( "NOT-IN-SET", f"Branch {repr(branch)} has no vacant {repr(role)} positions" ).dict4api

        empsNode.remove(posNodes[-1])
        self._save()

        return { 'result': True,
                 'branch' : branch,
                 'pos' : role,
                 'total': int( etree.XPath(f"count(employee[@pos='{role}'])")(empsNode) ),
                 'vacant': int( etree.XPath(f"count(employee[@pos='{role}' and not(@person)])")(empsNode) ),
               }

    #-------------
    def getBranchVacantPositions( self, branch_id ):
        return sorted( set( etree.XPath(f"//branch[@id='{branch_id}']/employees/employee[not(@person)]/@pos")(self._xmlstorage) ))


    #-------------
    def _userFuncSets(self,userid):
        empNodes = etree.XPath(f"//branch/employees/employee[@person='{userid}']")(self._xmlstorage)
        if len(empNodes)==0:
            return [] # unemployed
        else:
            branch = empNodes[0].getparent().getparent()

            whitelist = self._collectBranchFuncsets(branch) # returns set
            logger.info(f"Collected whitelist for branch '{branch.get('id')}' is {whitelist}")
            
            pos = empNodes[0].get("pos")
            roleNode = self._findRoleNode(pos,branch) # search role definition in branch of upper
            if roleNode is None:
                logger.error(f"Position '{pos}' used in branch '{branch.get('id')}' without role definition, please fix database")
                return []
            else:
                funcsets4role = set( etree.XPath("funcset/@id")(roleNode) )
                ret = whitelist & funcsets4role
                logger.info(f"Whitelist for '{userid}' is {whitelist}, role funcset for pos '{pos}' is {funcsets4role}, intersection is {ret}")
                return list(ret)

    #-------------
    def getBranchEnabledFuncsets(self,branch_id):
        try:
            branch_node = self._getBranchNodeS(branch_id)
        except configDataKeeper._internEx as ex:
            return []

        return  self._collectBranchFuncsets( branch_node )


    #-------------
    def listBranchRoles(self,branch_id, with_inherited, with_branchids ):
        try:          
            branchNode = self._getBranchNodeS(branch_id)
        except configDataKeeper._internEx as ex:
            return ex.dict4api
       
        roleSet = set( etree.XPath(f"{'ancestor-or-self' if with_inherited else 'self'}::branch/roles/role/@name")(branchNode) )

        if not with_branchids:
            return { 'result': True, 'roles': sorted(roleSet) }
        else:
            return { 'result': True, 'roles_in_branch': sorted( ((r,self._findRoleNode(r,branchNode).getparent().getparent().get('id')) for r in roleSet), 
                                                                key=lambda tup: tup[0] 
                                                              )
                   }
 
    #-------------
    def createBranchRole(self,branch_id, role_name, duties ):
        try:
            rolesNode = self._getBranchNodeS(branch_id,"roles")
        except configDataKeeper._internEx as ex:
            return ex.dict4api
       
        if len(etree.XPath(f"role[@name='{role_name}']")(rolesNode))>0:
            return configDataKeeper._internEx( 'ALREADY-EXISTS', f"Role {repr(role_name)} already defined in branch {repr(branch_id)}", bad_value=role_name ).dict4api

        roleNode = etree.SubElement(rolesNode,"role")
        roleNode.set("name",role_name)
        for d in duties:
            etree.SubElement(roleNode, "funcset").set("id",d)

        self._save()

        return {'result': True }
 
    #-------------
    def deleteBranchRole(self,branch_id, role_name ):
        try:
            rolesNode = self._getBranchNodeS(branch_id,"roles")
        except configDataKeeper._internEx as ex:
            return ex.dict4api
       
        roleNodes = etree.XPath(f"role[@name='{role_name}']")(rolesNode)
        if len(roleNodes)==0:
            return configDataKeeper._internEx( 'ROLE-UNKNOWN', f"Role {repr(role_name)} has no direct definition in branch {repr(branch_id)}", bad_value=role_name ).dict4api

        rolesNode.remove( roleNodes[0] )
        self._save()

        return {'result': True }
 

    #-------------

    #def _check_operator(self, operator_id):
    #    if operator_id is None or operator_id=="":
    #        raise configDataKeeper._internEx( 'OP-UNAUTHORIZED', "Operator not authorized or authorization expired" )

    #-------------

    def _get_operatorS_node(self, operator_id):
        #self._check_operator(operator_id)
        opnode = self._getUserNode(operator_id)
        if opnode is None:
            raise configDataKeeper._internEx( 'OP-UNKNOWN', f"Operator {repr(operator_id)} is unknown to the system" )
        return opnode

    #-------------

    def _get_operatorS_branch(self, operator_id):
        #self._check_operator(operator_id)
        opbranches = etree.XPath(f"//branch[employees/employee/@person='{operator_id}']")(self._xmlstorage)
        if len(opbranches)==0:
            raise configDataKeeper._internEx( 'FORBIDDEN-FOR-OP', f"Operator {repr(operator_id)} is nowhere employed " )
        return opbranches[0]
                                                
    #-------------

    def createUser(self,userid,secret,operator,pswlifetime=None,readablename="",sessionmax=None):

        if userid is None or secret is None or operator is None:
            return configDataKeeper._internEx('WRONG-FORMAT',f"Not all required parameters are given: user id:{repr(userid)}, secret:{repr(secret)}, operator:{repr(operator)}").dict4api

        if not self._getUserNode(userid) is None:
            return configDataKeeper._internEx('ALREADY-EXISTS',f"User '{userid}' already exists").dict4api

        try:
            self._get_operatorS_node(operator)
        except configDataKeeper._internEx as ex:
            return ex.dict4api

        logger.info(f"Creating record for new user '{userid}'")
        pnode = etree.XPath("/universe/registers/people_register")(self._xmlstorage)[0]
        pswTime=int(time.time())
      
        unode = etree.SubElement(pnode,"person")
        unode.set("id",userid)
        unode.set("secret",secret)
        unode.set("pswChangedAt",str(pswTime))
        unode.set("failures","0")
        unode.set("readableName",readablename)
        unode.set("sessionMax", str(self._dflt_sess_max if sessionmax is None else sessionmax))
        unode.set("createdBy",operator)
        unode.set("createdAt",str(pswTime))

        ret = { 'result': True, 'secret_changed': pswTime }
        if not pswlifetime is None and len(pswlifetime):
            expTime = pswTime + int(float(pswlifetime)*86400)
            unode.set("expireAt",str(expTime))
            ret["secret_expiration"] = expTime

        self._save()
        return ret

      
    #-------------

    def changeUser(self,userid,secret,operator,pswlifetime=None,readablename="",sessionmax=None):

        if userid is None or secret is None or operator is None:
            return configDataKeeper._internEx('WRONG-FORMAT',f"Not all required parameters are given: user id:{repr(userid)}, secret:{repr(secret)}, operator:{repr(operator)}").dict4api

        unode = self._getUserNode(userid)
        if unode is None:
            return configDataKeeper._internEx('USER-UNKNOWN',f"User {repr(userid)} is unknown").dict4api

        try:
            self._get_operatorS_node(operator)
        except configDataKeeper._internEx as ex:
            return ex.dict4api

        #if operator != userid:
        #    return configDataKeeper._internEx('FORBIDDEN-FOR-OP',"Password change is allowed only for user himself").dict4api

        logger.info(f"Changing registration data for user '{userid}'")
        pswTime=int(time.time())
        unode.set("secret",secret)
        unode.set("pswChangedAt",str(pswTime))
        unode.set("readableName", readablename)
        unode.set("sessionMax", str(self._dflt_sess_max if sessionmax is None else sessionmax))
        unode.set("failures","0")

        ret = { 'result': True, 'secret_changed': pswTime }
        if not pswlifetime is None and len(pswlifetime):
            expTime = pswTime + int(float(pswlifetime)*86400)
            unode.set("expireAt",str(expTime))                
            ret["secret_expiration"] = expTime
        elif "expireAt" in unode.attrib:
            unode.attrib.pop("expireAt")                

        changednode = etree.SubElement(unode,"changed")
        changednode.set("by",operator)
        changednode.set("at",str(pswTime))

        self._save()
        return ret

      
    #-------------

    def deleteUser(self,userid,operator):

        try:
            self._get_operatorS_node(operator)
        except configDataKeeper._internEx as ex:
            return ex.dict4api

        if userid is None:
            return configDataKeeper._internEx('WRONG-FORMAT',f"Not all required parameters are given: user id is {repr(userid)}").dict4api

        unode = self._getUserNode(userid)
        if unode is None:
            return configDataKeeper._internEx('USER-UNKNOWN',f"User {repr(userid)} is unknown").dict4api

        branches = self.userBranches(userid)
        if len(branches)!=0: 
            return configDataKeeper._internEx('USER-EMPLOYED',f"User '{userid}' is employed, fire him first").dict4api

        logger.info(f"Deleting user '{userid}'")
        unode.getparent().remove(unode)
        self._save()
        return { 'result': True }

    #-------------

    def _get_empNode_relOp(self, operator, userid):

        opbranch = self._get_operatorS_branch(operator)
        empNodes = etree.XPath(f"descendant-or-self::employee[@person='{userid}']") (opbranch)
        if len(empNodes)==0:
            raise configDataKeeper._internEx('FORBIDDEN-FOR-OP',f"User {repr(userid)} is not accountable to operator {repr(operator)}")
        return empNodes[0]
      
    #-------------

    def fireEmployee(self,userid, operator):

        if userid is None:
            return configDataKeeper._internEx('WRONG-FORMAT',f"Not all required parameters are given: user id is {repr(userid)}").dict4api
                          
        if self._getUserNode(userid) is None:
            return configDataKeeper._internEx('USER-UNKNOWN',f"User {repr(userid)} is unknown").dict4api

        branches = self.userBranches(userid)
        if len(branches)==0: 
            return configDataKeeper._internEx('ALREADY-UNEMPLOYED',f"User '{userid}' already unemployed").dict4api
        branch = branches[0]
 
        try:
           empNode = self._get_empNode_relOp(operator,userid)
        except configDataKeeper._internEx as ex:
            return ex.dict4api

        pos = empNode.get('pos')
        logger.info(f"Firing employee '{userid}' from position '{pos}' in '{branch}'")
        empNode.attrib.pop("person") # removing attribute - freeing position
        self._save()
        return { 'result': True, 'branch':branch, 'pos':pos }
      

    #-------------

    def _get_brNode_relOp(self, operator, branch):

        opbranch = self._get_operatorS_branch(operator)
        brNodes = etree.XPath(f"descendant-or-self::branch[@id='{branch}']") (opbranch)
        if len(brNodes)==0:
            raise configDataKeeper._internEx('FORBIDDEN-FOR-OP',f"Branch {repr(branch)} is not accountable to operator {repr(operator)}")
        return brNodes[0]
      
    #-------------

    def hireEmployee(self,userid,branch,pos, operator):

        if any(x is None or x=="" for x in (userid,branch,pos)):
            return configDataKeeper._internEx('WRONG-FORMAT',f"Not all required parameters are given: user id is {repr(userid)}, branch is {repr(branch)}, pos is {repr(pos)}").dict4api

        if self._getUserNode(userid) is None:
            return configDataKeeper._internEx('USER-UNKNOWN',f"User {repr(userid)} is unknown").dict4api

        branches = self.userBranches(userid)
        if len(branches)!=0: 
            return configDataKeeper._internEx('ALREADY-EMPLOYED',f"User '{userid}' already employed at {branches}").dict4api

        branchNodes = etree.XPath(f"//branch[@id='{branch}']")(self._xmlstorage)
        if len(branchNodes)==0: 
            return configDataKeeper._internEx('BRANCH-UNKNOWN',f"Branch '{branch}' does not exist").dict4api

        empNodes = etree.XPath(f"employees/employee[@pos='{pos}' and not(@person)]")(branchNodes[0])
        logger.info(f"We have {len(empNodes)} vacant positions for '{pos}' in '{branch}'")
        if len(empNodes)==0: 
            return configDataKeeper._internEx('NO-VACANT-POSITIONS',f"No vacant positions for '{pos}' in '{branch}'").dict4api

        try:
           self._get_brNode_relOp(operator,branch)
        except configDataKeeper._internEx as ex:
            return ex.dict4api

        logger.info(f"Hiring employee '{userid}' to position '{pos}' in '{branch}'")
        empNodes[0].set("person",userid)
        self._save()
        return { 'result': True }
      

    #-------------

    def empSubbranchesList(self,userid,allLevels,excludeOwn):
        if self._getUserNode(userid) is None:
            logger.warning(f"User '{userid}' is unknown")
            return { 'result': False, 'reason':'USER-UNKNOWN'}
        else:
            axe = 'descendant' if allLevels else 'child'
            brIds = set(etree.XPath(f"//branch[employees/employee/@person='{userid}']/branches/{axe}::branch/@id")(self._xmlstorage))
            if not excludeOwn:
                brIds |= set(etree.XPath(f"//employee[@person='{userid}']/../../@id")(self._xmlstorage))
            logger.info(f"Sub-branches for user '{userid}' are {repr(brIds)}")
            return { 'result': True, 
                     'subbranches': list(brIds), 
                   }

    #-------------
    def empFuncsetsList(self,userid):
        if self._getUserNode(userid) is None:
            logger.warning(f"User '{userid}' is unknown")
            return { 'result': False, 'reason':'USER-UNKNOWN'}
        else:
            return { 'result': True, 
                     'funcsets': self._userFuncSets(userid)
                   }

    #-------------

    def __empFunctionIds(self,userid):
        funcsAllowed = set()
        for x in self._userFuncSets(userid):
            funcsAllowed |= set(etree.XPath(f"//funcset[@id='{x}']/func/@id")(self._xmlstorage))
        funcsKnown = set( self.listFunctions("id")["values"] )
        funcs = funcsAllowed & funcsKnown
        logger.info(f"Functions for {userid} are {funcs} as an intersectoin of allowed {funcsAllowed} and known {funcsKnown}")
        return funcs

    #-------------

    def empFunctionsList(self,userid, prop="id"):
        if self._getUserNode(userid) is None:
            logger.warning(f"User '{userid}' is unknown")
            return { 'result': False, 'reason':'USER-UNKNOWN'}
        else:
            funcs = self.__empFunctionIds(userid)
            return { 'result': True, 
                     'prop' : prop,
                     'functions': list(set( self.reviewFunctions(prop,function_id=f)["props"][prop] for f in funcs )),
                   }

    #-------------

    def empFunctionsReview(self,userid, props):
        if self._getUserNode(userid) is None:
            logger.warning(f"User '{userid}' is unknown")
            return { 'result': False, 'reason':'USER-UNKNOWN'}
        else:
            funcs = self.__empFunctionIds(userid)
            return { 'result': True, 
                     'props' : props,
                     'functions': [ self.reviewFunctions(props,function_id=f)["props"] for f in funcs ],
                   }

    #-------------
    def branchEmployeesList(self,branchId,includeSubBranches):
        branchNodes = etree.XPath(f"//branch[@id='{branchId}']")(self._xmlstorage)
        if len(branchNodes)==0:
            logger.warning(f"Branch '{brachId}' is unknown")
            return { 'result': False, 'reason':'BRANCH-UNKNOWN'}
        else:
            return { 'result': True, 
                     'employees': etree.XPath( "descendant-or-self::employee/@person" if includeSubBranches else "employees/employee/@person"
                                             ) (branchNodes[0])
                   }

            
    #-------------

    _fpHow = {
       "id":          ("@id",                     lambda x: x ),
       "name":        ("@name",                   lambda x: x ),
       "title":       ("@title",                  lambda x: x ),
       "description": ("@descr",                  lambda x: x ),
       "callpath":    ("call/url[1]/text()[1]",   lambda x: x.partition("?")[0] ),
       "method":      ("call/@method",            lambda x: x ),
       "contenttype": ("call/body/@content-type", lambda x: x ),
    }

    #-------------

    def listFunctions(self,prop):

        if not prop in configDataKeeper._fpHow.keys():
            logger.error(f"Property {repr(prop)} is unknown")
            return { 'result': False, 'reason':'WRONG-FORMAT' }

        #catsTree = self._getCatalogues()
        rets = etree.XPath( "/catalogues/functions_catalogue/function/"+configDataKeeper._fpHow[prop][0] )(self._xmlcats)

        logger.info(f"Property {repr(prop)} values for known functions are: {rets}")

        return { 'result': True, 
                 'property': prop,
                 'values': sorted(set( configDataKeeper._fpHow[prop][1](x) for x in rets ))
               }


    #-------------

    def reviewFunctions(self,props,function_id=None):

        propl = props.split(",")
        if not all(prop in configDataKeeper._fpHow.keys() for prop in propl):
            return configDataKeeper._internEx('WRONG-FORMAT',f"One or more of properties in {repr(propl)} are unknown").dict4api

        #catsTree = self._getCatalogues()
        funcnodes = etree.XPath( "/catalogues/functions_catalogue/function" + ("" if function_id is None else f"[@id='{function_id}']") )(self._xmlcats)

        if len(funcnodes)==0 and not function_id is None:
            return configDataKeeper._internEx('FUNCTION-UNKNOWN',f"Function {function_id} is not described in catalogue").dict4api

        resGen = ( dict( ( p,
                           configDataKeeper._fpHow[p][1](etree.XPath(configDataKeeper._fpHow[p][0])(f)[0])
                          ) for p in propl if len(etree.XPath(configDataKeeper._fpHow[p][0])(f))>0
                       ) for f in funcnodes )

        if function_id is None:
            ret = { 'result': True,'functions': list(resGen) }
        else:    
            ret = { 'result': True,'props': next(resGen) , "function_id":function_id}
        return ret

    #-------------

    def getFunctionDef(self,funcId,pureXml,header=""):
        #catsTree = self._getCatalogues()
        funcNodes = etree.XPath(f"/catalogues/functions_catalogue/function[@id='{funcId}']")(self._xmlcats)
        if len(funcNodes)==0:
            logger.warning(f"Function '{funcId}' is unknown")
            return { 'result': False, 'reason':'FUNCTION-UNKNOWN'}
        else:
            fDef = header + etree.tostring(funcNodes[0], pretty_print=True, encoding='unicode')            
            if pureXml:
                return fDef
            else:
                return { 'result': True, 'definition': fDef  }



    #-------------

    def postFunctionDef(self,funcDescrText):

        try:
            newFuncTree = etree.fromstring(funcDescrText, parser=self._parser)
        except Exception as err:
            logger.error(f"Cannot parse new function description as XML, error {str(type(err))}, details:\n  {repr(err)}.")
            return { 'result': False, 'reason':'WRONG-DATA', 'details':repr(err) }

        funcId = newFuncTree.get("id",None)
        if funcId is None:
            return { 'result': False, 'reason':'WRONG-DATA', 'details':'Function does not have "id" attribute' }

        funcsCat = etree.XPath(f"/catalogues/functions_catalogue")(self._xmlcats)[0]
        funcNodes = etree.XPath(f"function[@id='{funcId}']")(funcsCat)
        if len(funcNodes)==0:
            logger.info(f"Function '{funcId}' is new")
            funcsCat.append(newFuncTree)
            ret = { 'result': True, 'function_id':funcId, 'status':'APPENDED'}
        else:
            logger.info(f"Function '{funcId}' to be replaced")
            oldTxt = etree.tostring(funcNodes[0], pretty_print=True, encoding='unicode')
            funcsCat.replace(funcNodes[0],newFuncTree)
            ret = { 'result': True, 'function_id':funcId, 'status':'REPLACED', 'old_definition': oldTxt  }

        self._save(catalogues=True)
        return ret


    #-------------

    def deleteFunctionDef(self,funcId):

        if funcId is None:
            return { 'result': False, 'reason':'WRONG-FORMAT' }

        funcsCat = etree.XPath(f"/catalogues/functions_catalogue")(self._xmlcats)[0]
        funcNodes = etree.XPath(f"function[@id='{funcId}']")(funcsCat)

        if len(funcNodes)==0:
            logger.warning(f"Function '{funcId}' is unknown")
            return { 'result': False, 'reason':'FUNCTION-UNKNOWN'}

        logger.info(f"Function '{funcId}' to be deleted")
        oldTxt = etree.tostring(funcNodes[0], pretty_print=True, encoding='unicode')
        funcsCat.remove(funcNodes[0])
        self._save(catalogues=True)
        return { 'result': True, 'function_id':funcId, 'status':'DELETED', 'old_definition': oldTxt  }


    #-------------
    def modifyFuncTagset(self, funcId, method, tagset, read_only=False):

        if any(x is None or x=="" for x in (funcId,method)):
            return configDataKeeper._internEx('WRONG-FORMAT',f"Required parameter not given: funcId {repr(funcId)}, method {repr(method)}").dict4api
        funcNodes = etree.XPath(f"/catalogues/functions_catalogue/function[@id='{funcId}']")(self._xmlcats)
        if len(funcNodes)==0:
            return configDataKeeper._internEx('FUNCTION-UNKNOWN',f"Function {repr(funcId)} is unknown").dict4api

        old_tagset = set(funcNodes[0].get("tags","").split(","))

        if method=='SET' and not read_only:
            new_tagset = tagset
        elif method=='OR':
            new_tagset = tagset | old_tagset
        elif method=='AND':
            new_tagset = tagset & old_tagset
        elif method=='MINUS':
            new_tagset = old_tagset - tagset
        else:
            return configDataKeeper._internEx('WRONG-FORMAT',f"Method {repr(method)} is unapplicable",wrong_value=method).dict4api

        retTs = ",".join(new_tagset)
        if not read_only:
            funcNodes[0].set( "tags", retTs )
            self._save(catalogues=True)

        return {'result': True, 'tagset': retTs }
 
    #-------------
    def getAgents(self):
        return self._agents_keeper.get_all_agent_ids()

    #-------------
    def getSubBranchesOfAgent(self,agentid):

        branch_id = self._agents_keeper.get_branch_name(agentid)
        logger.info("requested subbranches of owner of agent {repr(agentid)} that is {repr(branch_id)}")
        ret =  etree.XPath(f"//branch[@id='{branch_id}']/descendant-or-self::branch/@id")(self._xmlstorage)
        logger.info("result is {repr(ret)} with length {len(ret)}")
        return ret

    #-------------
    
    def registerAgentInBranch( self, branch_id, agent_id, move=False,
                               descr="", location="", tags="", extraxml="" 
                             ):
        if branch_id=="*ROOT*":
            branch_id = etree.XPath(f"/universe/branches/branch[1]/@id")(self._xmlstorage)[0]
            logger.info(f"Branch ID {repr(branch_id)} is taken as a *ROOT*")

        current = self._agents_keeper.get_agent_dict(agent_id, with_tags=False)

        if not move:

            if not current is None:
                return configDataKeeper._internEx( 'ALREADY-EXISTS', f"Agent {repr(agent_id)} already registered in branch {repr(current['branch'])}", bad_value=agent_id ).dict4api

            try:
                etree.fromstring( f'<extra>{extraxml}</extra>')
            except Exception as ex:
                return configDataKeeper._internEx('WRONG-FORMAT',f"extraxml field does not fit into XML format, details: {repr(ex)}").dict4api


        else:

            if current is None:
                return configDataKeeper._internEx( 'AGENT-UNKNOWN', f"Agent {repr(agent_id)} is never registered", bad_value=agent_id ).dict4api
            curr_br_name = current['branch']
            curr_branch_nodes = etree.XPath( f"//branch[@id='{curr_br_name}']" )(self._xmlstorage)   
            if len(curr_branch_nodes)==0:
                return configDataKeeper._internEx( 'DATABASE-ERROR', f"Branch {repr(curr_br_name)} referenced from agent {repr(agent_id)} does not longer exist" ).dict4api
            if len(etree.XPath(f"descendant-or-self::branch[@id='{branch_id}']")(curr_branch_nodes[0]))!=1:
                return configDataKeeper._internEx( 'NOT-IN-SET', f"Branch {repr(branch_id)} is not a subsidiary of a branch {repr(curr_br_name)} containing agent {repr(agent_id)}", bad_value=branch_id ).dict4api

            self.unregisterAgent(agent_id )

        self._agents_keeper.add_agent( agent_id, branch_id, descr, location, extraxml, filter(None,map(str.strip,tags.split(","))) )
        return {'result': True }
 
    #-------------
    def unregisterAgent(self, agent_id ):

        if not self._agents_keeper.delete_agent(agent_id):
           return configDataKeeper._internEx( 'AGENT-UNKNOWN', f"Agent {repr(agent_id)} is never registered", bad_value=agent_id ).dict4api

        return {'result': True }
 
    #-------------

    def agentDetailsXml(self, agent_id ):

        agdict = self._agents_keeper.get_agent_dict(agent_id, with_tags=True)
        if agdict is None:
            return configDataKeeper._internEx( 'AGENT-UNKNOWN', f"Agent {repr(agent_id)} is never registered", bad_value=agent_id ).dict4api

        agent_element = etree.Element("aginfo")
        etree.SubElement(agent_element, "descr").text = str(agdict['descr'])
        etree.SubElement(agent_element, "location").text = str(agdict['location'])
        etree.SubElement(agent_element, "extra").text = str(agdict['extra'])
        for tag in agdict['tags']:
            etree.SubElement(agent_element, "tag").text = str(tag)

        return { 'result': True, 'details': etree.tostring(agent_element, pretty_print=True, encoding='unicode')  }
 
    #-------------

    def agentDetailsJson(self, agent_id ):

        agdict = self._agents_keeper.get_agent_dict(agent_id, with_tags=True)
        if agdict is None:
            return configDataKeeper._internEx( 'AGENT-UNKNOWN', f"Agent {repr(agent_id)} is never registered", bad_value=agent_id ).dict4api
        
        return { 'result': True, 
                 'details': {
                     'descr': agdict['descr'],
                     'location': agdict['location'],
                     'tags': ",".join(agdict['tags']),
                     'extra': agdict['extra'],
                 }
               }
 
    #-------------

    def listAgents( self, branch_id, with_subsids, with_locs ):

        pfx = '/universe/branches/branch' if branch_id=='*ALL*' else f'//branch[@id="{branch_id}"]'
        axe = 'descendant-or-self' if with_subsids else 'self'

        br_ids = etree.XPath(f'{pfx}/{axe}::branch/@id')(self._xmlstorage)
        ags = self._agents_keeper.get_agents_by_branch_list(br_ids)

        if not with_locs:
            rep =( a[0] for a in ags )
        else:
            rep = (  { 'agent':a[0], 'branch':a[1] } for a in ags )

        return { 'result': True, 
                 'report': list(rep)
               }

    #-------------

    class _internEx(Exception):

        def __init__(self, reason, warnmessage, **kwargs):
            logger.warning(warnmessage)
            self.dict4api = { 'result':False, 'reason':reason, 'warning':warnmessage }
            self.dict4api.update(kwargs)
       
    #-------------

#--------------------------------------------------------------------------------------------------------------
# Some self-test functionality

if __name__ == '__main__':

    import configTestLogging
    configTestLogging.config(_logName)

    #~~~~~~~~~~~~~~~~~~~~~~~

    def main():        
        test = configDataKeeper("DATA/everything.xml","DATA/catalogues.xml")
        test.load()
        test._save()

    main()

