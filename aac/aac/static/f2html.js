// Generic utils for f2html.xsl

//---------------------------

function f2html_callSync(url,body,method,contenttype) {

    console.log("Executing request " + JSON.stringify(url) + " with sync "+ method);

    var xhttp = new XMLHttpRequest();
    xhttp.open(method, url, false);
    if(contenttype!="")
        xhttp.setRequestHeader('Content-Type', contenttype)  
    xhttp.send(body);
    console.log("Received responce ", xhttp.responseText);
    return xhttp.responseText;
}

//---------------------------

function f2html_serialize_str(value) {
    return value;
}

function f2html_serialize_bool(value) {
    return value?"yes":"no";
}

function f2html_serialize_timestamp(value) {
    return String(new Date(value*1000));
}

function f2html_serialize_duration(value) {
    return String(value);
}

function f2html_serialize_number(value) {
    return String(value);
}

function f2html_serialize_sha256(value) {
    return "******"+String(value).slice(-4);
}

function f2html_serialize_password(value) {
    return "**********"
}

function f2html_serialize_url(value) {
    return value
}

function f2html_serialize_var(value) {
    return String(value) // ? need clarification what is "var" purpose
}

//---------------------------
