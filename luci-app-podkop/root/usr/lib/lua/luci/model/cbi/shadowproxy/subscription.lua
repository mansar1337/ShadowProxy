local uci = require "luci.model.uci".cursor()
local sys = require "luci.sys"
local util = require "luci.util"

m = Map("shadowproxy", translate("ShadowProxy Subscription"), translate("Fetch and import nodes from subscription URL."))
m.template = "shadowproxy/subscription"

s = m:section(NamedSection, "subscription", "subscription", translate("Subscription Source"))
s.addremove = false
s.anonymous = true

url = s:option(Value, "url", translate("URL"))
url.rmempty = false
url.datatype = "string"

base64 = s:option(Flag, "decode_base64", translate("Decode Base64"))
base64.rmempty = false
base64.default = "0"

ua = s:option(Flag, "custom_ua", translate("Custom User-Agent"))
ua.rmempty = false
ua.default = "0"

function m.on_after_commit(self)
    local url_value = uci:get("shadowproxy", "subscription", "url")
    if not url_value or url_value == "" then
        return
    end

    local cmd = "/usr/bin/shadowproxy-subscription --url " .. util.shellquote(url_value)

    if uci:get("shadowproxy", "subscription", "decode_base64") == "1" then
        cmd = cmd .. " --base64"
    end

    if uci:get("shadowproxy", "subscription", "custom_ua") == "1" then
        cmd = cmd .. " --ua"
    end

    cmd = cmd .. " >/tmp/shadowproxy_subscription.log 2>&1"
    sys.call(cmd)
end

return m
