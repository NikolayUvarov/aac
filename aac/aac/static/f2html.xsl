<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="html" indent="yes" />
<xsl:strip-space elements="insert concat sha256"/>

<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->

<xsl:template match="function">
<html>
	<head>
		<script src="/aac/static/minicrypto.js"></script>
		<script src="/aac/static/jsonpath.js"></script>
		<script type="text/javascript" src="/aac/static/f2html.js"></script>
                <link rel="stylesheet" type="text/css" href="/aac/static/data-tooltip.css"/>
                <link rel="stylesheet" type="text/css" href="/aac/static/f2html.css"/>
		<script>
			//-------------
			function f2html_proceedActions() {
				var strg={} //args and results storage
				<xsl:apply-templates select="in/*" mode="proceed"/>
				//-----------
				var callCmd = '<xsl:apply-templates select="call/url/*|call/url/text()" mode="build-call"/>';
				var callBdy = '<xsl:apply-templates select="call/body/*|call/body/text()" mode="build-call"/>';
				var callMtd = '<xsl:value-of select="call/@method"/>';
				var callTyp = '<xsl:value-of select="call/body/@content-type"/>';
				console.log("Call "+callMtd+" command prepared: '"+callCmd+"' with body '"+callBdy+"' of type '"+callTyp+"'" );
				document.getElementById("f2html_inp").removeAttribute("open");
				document.getElementById("f2html_rawSect").setAttribute("open","");
				document.getElementById("f2html_parsedSect").setAttribute("open","");
				setTimeout( f2html_makeCall, 0, callCmd,callBdy,callMtd,callTyp,strg );
			}
			//-------------
			function f2html_makeCall(callCmd,callBdy,callMtd,callTyp,strg) {
				var rawRes = f2html_callSync(callCmd,callBdy,callMtd,callTyp);
				document.getElementById("f2html_rawRes").innerText = rawRes;
				<xsl:apply-templates select="out" mode="proceed"/>
			}
			//-------------
                        <xsl:for-each select="in/bool[@entry]">
				<xsl:variable name="boolitem" select="."/>
				function f2html_click_<xsl:value-of select="@entry"/>(cb) {
                                  <xsl:for-each select="../*[@if-yes=$boolitem/@entry]">
				      if(cb.checked) document.getElementById('f2htmlID_<xsl:value-of select="@entry"/>').removeAttribute('disabled'); else document.getElementById('f2htmlID_<xsl:value-of select="@entry"/>').setAttribute('disabled','');
                                  </xsl:for-each>
				}
                        </xsl:for-each>
			//-------------
		</script>
		<title><xsl:value-of select="@name"/></title>
	</head>
	<body> 
	<section class='f2html_all'>
		<span class='f2html_hdr'>
			<xsl:if test="@descr"><xsl:attribute name="data-tooltip"><xsl:value-of select="@descr"/></xsl:attribute></xsl:if>
			<xsl:value-of select="@title"/>
                </span>
		<details id="f2html_inp" open=""> <summary/>
			<form>
				<xsl:apply-templates mode="collect" select="in/*" />
				<button type="button" onclick="if(this.form.reportValidity()) f2html_proceedActions();">Execute</button>
			</form>
                </details>
		<hr/>
		<details id="f2html_parsedSect"> <summary/>
			<table id="f2html_parsedTable"></table>
		</details>
		<hr/>
		<details id="f2html_rawSect"> <summary/>
			<span id="f2html_rawRes"></span>
                </details>

	</section> 
	</body>
</html>
</xsl:template>
  
<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->

<xsl:template match="str[@entry]" mode="collect">
		<p class="f2html_param">
			<xsl:if test="@descr"><xsl:attribute name="data-tooltip"><xsl:value-of select="@descr"/></xsl:attribute></xsl:if>

			<label for="f2htmlID_{@entry}"><xsl:value-of select="@title"/>:</label>
			<input type="text" name="{@entry}" id="f2htmlID_{@entry}" value="{@default}">
				<xsl:if test="not(@optional='yes')"><xsl:attribute name="required"/></xsl:if>
			</input>
		</p>
</xsl:template>

<xsl:template match="str[@entry]" mode="proceed">
				strg['<xsl:value-of select="@entry"/>'] = document.getElementById('f2htmlID_<xsl:value-of select="@entry"/>').value;
				console.log('Parameter <xsl:value-of select="@entry"/> is ' + strg['<xsl:value-of select="@entry"/>']);
</xsl:template>

<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->

<xsl:template match="password[@entry]" mode="collect">
		<p class="f2html_param">
			<xsl:if test="@descr"><xsl:attribute name="data-tooltip"><xsl:value-of select="@descr"/></xsl:attribute></xsl:if>

			<label for="f2htmlID_{@entry}"><xsl:value-of select="@title"/>:</label>
			<input type="password" id="f2htmlID_{@entry}">
				<xsl:if test="not(@optional='yes')"><xsl:attribute name="required"/></xsl:if>
                        </input>
		</p>
</xsl:template>

<xsl:template match="password[@entry]" mode="proceed">
				strg['<xsl:value-of select="@entry"/>'] = document.getElementById('f2htmlID_<xsl:value-of select="@entry"/>').value;
				console.log('Password <xsl:value-of select="@entry"/> length is ' + strg['<xsl:value-of select="@entry"/>'].length);
</xsl:template>

<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->

<xsl:template match="bool[@entry]" mode="collect">
		<p class="f2html_param">
			<xsl:if test="@descr"><xsl:attribute name="data-tooltip"><xsl:value-of select="@descr"/></xsl:attribute></xsl:if>

			<label for="f2htmlID_{@entry}">
				<input type="checkbox" name="{@entry}" id="f2htmlID_{@entry}" onclick="f2html_click_{@entry}(this)">
					<xsl:if test="@default='yes'"><xsl:attribute name="checked"/></xsl:if>
                                </input>
				<span><xsl:value-of select="@title"/></span>
			</label>
		</p>
</xsl:template>

<xsl:template match="bool[@entry]" mode="proceed">
				strg['<xsl:value-of select="@entry"/>'] = document.getElementById('f2htmlID_<xsl:value-of select="@entry"/>').checked ? "yes":"no";
				console.log('Parameter <xsl:value-of select="@entry"/> is ' + strg['<xsl:value-of select="@entry"/>']);
</xsl:template>

<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->

<xsl:template match="duration[@entry]" mode="collect">
		<p class="f2html_param">
			<xsl:if test="@descr"><xsl:attribute name="data-tooltip"><xsl:value-of select="@descr"/></xsl:attribute></xsl:if>

			<label for="f2htmlID_{@entry}"><xsl:value-of select="@title"/>:</label>
			<input type="number" name="{@entry}" id="f2htmlID_{@entry}" min="0" value="{@default}">
				<xsl:if test="not(@optional='yes')"><xsl:attribute name="required"/></xsl:if>
			</input>
		</p>
</xsl:template>

<xsl:template match="duration[@entry]" mode="proceed">
				strg['<xsl:value-of select="@entry"/>'] = document.getElementById('f2htmlID_<xsl:value-of select="@entry"/>').value;
				console.log('Parameter <xsl:value-of select="@entry"/> is ' + strg['<xsl:value-of select="@entry"/>']);
</xsl:template>

<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->
<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->

<xsl:template name="procNew">
  <xsl:param name = "newName" />
  <xsl:if test="$newName!=''">
				strg['<xsl:value-of select="$newName"/>'] = 
					</xsl:if>
</xsl:template>

<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->

<xsl:template match="insert[@from]" mode="proceed">
  <xsl:text>strg['</xsl:text> 
  <xsl:value-of select="@from"/>
  <xsl:text>']</xsl:text> 
</xsl:template>


<xsl:template match="insert[@from]" mode="build-call">
  <xsl:text>' + (</xsl:text> 
  <xsl:if test="@if-yes">
    <xsl:text>strg['</xsl:text> <xsl:value-of select="@if-yes"/> <xsl:text>']</xsl:text>
    <xsl:text>!='yes'?'':</xsl:text> 
  </xsl:if>
  <xsl:text>strg['</xsl:text> <xsl:value-of select="@from"/> <xsl:text>']</xsl:text>
  <xsl:text>) + '</xsl:text> 
</xsl:template>

<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->

<xsl:template match="text" mode="proceed">
  <xsl:value-of select="text()"/>
</xsl:template>


<xsl:template match="text" mode="build-call">
  <xsl:text>' + (</xsl:text> 
  <xsl:if test="@if-yes">
    <xsl:text>strg['</xsl:text> <xsl:value-of select="@if-yes"/> <xsl:text>']</xsl:text>
    <xsl:text>!='yes'?'':</xsl:text> 
  </xsl:if>
  <xsl:text>'</xsl:text> <xsl:value-of select="text()"/> 
  <xsl:text>') + '</xsl:text> 
</xsl:template>

<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->

<xsl:template match="sha256" mode="proceed">
  <xsl:call-template name="procNew"> <xsl:with-param name="newName" select = "@new" /> </xsl:call-template>
  <xsl:text>minicrypto_sha256( encodeURI(</xsl:text><xsl:apply-templates mode="proceed"/><xsl:text>))</xsl:text>
  <xsl:if test="@new">
				console.log('New item <xsl:value-of select="@new"/> built: ' + strg['<xsl:value-of select="@new"/>']);
  </xsl:if>
</xsl:template>

<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->

<xsl:template match="concat" mode="proceed">
  <xsl:call-template name="procNew"> <xsl:with-param name="newName" select = "@new" /> </xsl:call-template>
  <xsl:text>[</xsl:text> 
  <xsl:for-each select="*">
    <xsl:apply-templates select="." mode="proceed"/> 
    <xsl:text>,</xsl:text>
  </xsl:for-each>
  <xsl:text>""].join("")</xsl:text>
</xsl:template>

<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->

<xsl:template match="out[@format='json']" mode="proceed">
				var jsonRes = JSON.parse( rawRes );
				console.log("Json-parsed result is: ",jsonRes);
				<xsl:apply-templates select="*" mode="jsonResult"/> 
</xsl:template>

<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->

<xsl:template match="done|failed|execution-state" mode="jsonResult">
  <xsl:if test="position()>1">				else </xsl:if>
  <xsl:if test="@if and @eq">if(String(jsonPath(jsonRes,'<xsl:value-of select="@if"/>')) == '<xsl:value-of select="@eq"/>')</xsl:if>
				{
					console.log("Execution result is: ","<xsl:value-of select="@title"/>");
					document.getElementById("f2html_parsedTable").innerHTML = 
					  "&lt;thead>&lt;tr>&lt;th colspan='3' class='f2html_res_<xsl:value-of select="name()"/>'><xsl:value-of select="@title"/>&lt;/th>&lt;/tr>&lt;/thead>";
					<xsl:apply-templates select="*" mode="jsonResult"/> 
  <xsl:if test="@nextcheckdelay">
					var pollCmd = callCmd, poolBdy=callBdy, pollMtd=callMtd, pollTyp=callTyp; 
    <xsl:if test="poll">
					pollCmd = '<xsl:apply-templates select="poll/url/*|poll/url/text()" mode="build-call"/>';
					pollBdy = '<xsl:apply-templates select="poll/body/*|poll/body/text()" mode="build-call"/>';
					pollMtd = '<xsl:value-of select="poll/@method"/>';
					pollTyp = '<xsl:value-of select="poll/body/@content-type"/>';
    </xsl:if>
					console.log("Poll "+pollMtd+" command prepared: '"+pollCmd+"' with body '"+pollBdy+"' of type '"+pollTyp+"'");
					setTimeout( f2html_makeCall, <xsl:value-of select="@nextcheckdelay"/>*1000, pollCmd,pollBdy,pollMtd,pollTyp,strg );
  </xsl:if>
				}
</xsl:template>

<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->

<xsl:template match="*[@id and @select]" mode="jsonResult">
					strg['<xsl:value-of select="@id"/>'] = jsonPath(jsonRes,"<xsl:value-of select='@select'/>");
					document.getElementById("f2html_parsedTable").insertAdjacentHTML( "beforeend", "&lt;tr>"
					  +"&lt;th><xsl:value-of select='@title'/>&lt;/th>"
					  +"&lt;td><xsl:value-of select='@id'/>&lt;/td>"
					  +"&lt;td>" + f2html_serialize_<xsl:value-of select="name()"/>(strg['<xsl:value-of select="@id"/>']) + "&lt;/td>"
					  +"&lt;/tr>");
</xsl:template>


<xsl:template match="poll" mode="jsonResult"/>

<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->
<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->
<xsl:template mode="proceed" match="*"></xsl:template>
<xsl:template mode="collect" match="*"></xsl:template>
<!-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ -->

</xsl:stylesheet>

