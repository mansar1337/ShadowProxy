PODKOP_LIB="/usr/lib/podkop"
. "$PODKOP_LIB/helpers.sh"
. "$PODKOP_LIB/sing_box_config_manager.sh"

_is_valid_port() {
    local port="$1"
    [ -n "$port" ] && [ "$port" -ge 1 ] 2> /dev/null && [ "$port" -le 65535 ] 2> /dev/null
}

_normalize_transport() {
    local transport="$1"
    case "$transport" in
    "" | raw) echo "tcp" ;;
    tcp | udp | grpc | ws | http | httpupgrade | xhttp) echo "$transport" ;;
    *)
        log "Invalid transport '$transport' in proxy URL" "error"
        return 1
        ;;
    esac
}

_normalize_bool_param_to_singbox() {
    local value="$1"
    local param_name="$2"
    local protocol_name="$3"

    case "$value" in
    "" | 0 | false | FALSE | False) echo "false" ;;
    1 | true | TRUE | True) echo "true" ;;
    *)
        log "Invalid $param_name value '$value' for $protocol_name. Expected true/false or 1/0." "error"
        return 1
        ;;
    esac
}

sing_box_cf_add_dns_server() {
    local config="$1"
    local type="$2"
    local tag="$3"
    local server="$4"
    local domain_resolver="$5"
    local detour="$6"

    local server_address server_port
    server_address=$(url_get_host "$server")
    server_port=$(url_get_port "$server")

    case "$type" in
    udp)
        [ -z "$server_port" ] && server_port=53
        config=$(sing_box_cm_add_udp_dns_server "$config" "$tag" "$server_address" "$server_port" "$domain_resolver" \
            "$detour")
        ;;
    dot)
        [ -z "$server_port" ] && server_port=853
        config=$(sing_box_cm_add_tls_dns_server "$config" "$tag" "$server_address" "$server_port" "$domain_resolver" \
            "$detour")
        ;;
    doh)
        [ -z "$server_port" ] && server_port=443
        local path headers
        path=$(url_get_path "$server")
        headers="" # TODO(ampetelin): implement it if necessary
        config=$(sing_box_cm_add_https_dns_server "$config" "$tag" "$server_address" "$server_port" "$path" "$headers" \
            "$domain_resolver" "$detour")
        ;;
    *)
        log "Unsupported DNS server type: $type." "error"
        return 1
        ;;
    esac

    echo "$config"
}

sing_box_cf_add_mixed_inbound_and_route_rule() {
    local config="$1"
    local tag="$2"
    local listen_address="$3"
    local listen_port="$4"
    local outbound="$5"

    config=$(sing_box_cm_add_mixed_inbound "$config" "$tag" "$listen_address" "$listen_port")
    config=$(sing_box_cm_add_route_rule "$config" "" "$tag" "$outbound")

    echo "$config"
}

sing_box_cf_add_proxy_outbound() {
    local config="$1"
    local section="$2"
    local url="$3"
    local udp_over_tcp="$4"

    url=$(url_decode "$url")
    url=$(url_strip_fragment "$url")

    local scheme
    scheme="$(url_get_scheme "$url")"
    case "$scheme" in
    socks4 | socks4a | socks5)
        local tag host port version userinfo username password udp_over_tcp

        tag=$(get_outbound_tag_by_section "$section")
        host=$(url_get_host "$url")
        port=$(url_get_port "$url")
        version="${scheme#socks}"
        if [ "$scheme" = "socks5" ]; then
            userinfo=$(url_get_userinfo "$url")
            if [ -n "$userinfo" ]; then
                username="${userinfo%%:*}"
                password="${userinfo#*:}"
            fi
        fi
        config="$(sing_box_cm_add_socks_outbound \
            "$config" \
            "$tag" \
            "$host" \
            "$port" \
            "$version" \
            "$username" \
            "$password" \
            "" \
            "$([ "$udp_over_tcp" == "1" ] && echo 2)" # if udp_over_tcp is enabled, enable version 2
        )"
        ;;
    vless)
        local tag host port uuid flow packet_encoding transport
        tag=$(get_outbound_tag_by_section "$section")
        host=$(url_get_host "$url")
        port=$(url_get_port "$url")
        uuid=$(url_get_userinfo "$url")
        flow=$(url_get_query_param "$url" "flow")
        packet_encoding=$(url_get_query_param "$url" "packetEncoding")
        transport=$(url_get_query_param "$url" "type")

        if [ -z "$uuid" ] || [ -z "$host" ] || ! _is_valid_port "$port"; then
            log "Invalid VLESS URL: missing required uuid/host/port fields" "error"
            return 1
        fi

        local normalized_transport
        normalized_transport=$(_normalize_transport "$transport") || {
            log "Invalid VLESS URL: unsupported transport '$transport'" "error"
            return 1
        }

        # Pass normalized network transport so sing-box knows the correct
        # network field (e.g. "tcp", "ws", "grpc", "httpupgrade", "xhttp").
        # Previously always passed "" which caused sing-box to fall back to
        # its default and ignore the transport block in some cases.
        local vless_network
        case "$normalized_transport" in
            tcp|raw)   vless_network="" ;;   # sing-box default, omit field
            *)         vless_network="$normalized_transport" ;;
        esac

        config=$(sing_box_cm_add_vless_outbound "$config" "$tag" "$host" "$port" "$uuid" "$flow" "$vless_network" "$packet_encoding")
        config=$(_add_outbound_security "$config" "$tag" "$url")
        config=$(_add_outbound_transport "$config" "$tag" "$url")
        ;;
    ss)
        local userinfo tag host port method password udp_over_tcp transport

        userinfo=$(url_get_userinfo "$url")
        if ! is_shadowsocks_userinfo_format "$userinfo"; then
            userinfo=$(base64_decode "$userinfo")
            if [ $? -ne 0 ]; then
                log "Cannot decode shadowsocks userinfo or it does not match the expected format. Aborted." "fatal"
                exit 1
            fi
        fi

        tag=$(get_outbound_tag_by_section "$section")
        host=$(url_get_host "$url")
        port=$(url_get_port "$url")
        method="${userinfo%%:*}"
        password="${userinfo#*:}"
        transport=$(url_get_query_param "$url" "type")

        if [ -z "$method" ] || [ -z "$password" ] || [ -z "$host" ] || ! _is_valid_port "$port"; then
            log "Invalid Shadowsocks URL: missing required method/password/host/port fields" "error"
            return 1
        fi
        if [ -z "$transport" ]; then
            transport="tcp"
            log "Shadowsocks URL has no transport type, using default '$transport'" "warn"
        fi
        if ! _normalize_transport "$transport" > /dev/null; then
            log "Invalid Shadowsocks URL: unsupported transport '$transport'" "error"
            return 1
        fi

        config=$(
            sing_box_cm_add_shadowsocks_outbound \
                "$config" \
                "$tag" \
                "$host" \
                "$port" \
                "$method" \
                "$password" \
                "" \
                "$([ "$udp_over_tcp" == "1" ] && echo 2)" # if udp_over_tcp is enabled, enable version 2
        )

        local ss_obfs ss_padding
        ss_obfs=$(url_get_query_param "$url" "obfs")
        ss_padding=$(url_get_query_param "$url" "padding")
        if [ -n "$ss_obfs" ]; then
            log "Shadowsocks obfs option detected: $ss_obfs" "debug"
        fi
        if [ -n "$ss_padding" ]; then
            log "Shadowsocks padding option detected: $ss_padding" "debug"
        fi
        config=$(_add_outbound_transport "$config" "$tag" "$url")
        ;;
    trojan)
        local tag host port password transport sni alpn
        tag=$(get_outbound_tag_by_section "$section")
        host=$(url_get_host "$url")
        port=$(url_get_port "$url")
        password=$(url_get_userinfo "$url")
        transport=$(url_get_query_param "$url" "type")
        sni=$(url_get_query_param "$url" "sni")
        alpn=$(url_get_query_param "$url" "alpn")

        if [ -z "$password" ] || [ -z "$host" ] || ! _is_valid_port "$port"; then
            log "Invalid Trojan URL: missing required password/host/port fields" "error"
            return 1
        fi
        if [ -z "$transport" ]; then
            transport="tcp"
            log "Trojan URL has no transport type, using default '$transport'" "warn"
        fi
        if ! _normalize_transport "$transport" > /dev/null; then
            log "Invalid Trojan URL: unsupported transport '$transport'" "error"
            return 1
        fi
        if [ -z "$sni" ]; then
            sni="$host"
            log "Trojan URL has no sni, using host '$host'" "warn"
        fi
        if [ -z "$alpn" ]; then
            alpn="h2,http/1.1"
            log "Trojan URL has no alpn, using default '$alpn'" "warn"
        fi
        config=$(sing_box_cm_add_trojan_outbound "$config" "$tag" "$host" "$port" "$password")
        config=$(_add_outbound_security "$config" "$tag" "$url")
        config=$(_add_outbound_transport "$config" "$tag" "$url")
        ;;
    hysteria2 | hy2)
        local tag host port password obfuscator_type obfuscator_password upload_mbps download_mbps sni alpn transport hop_interval
        tag=$(get_outbound_tag_by_section "$section")
        host=$(url_get_host "$url")
        port="$(url_get_port "$url")"
        password=$(url_get_userinfo "$url")
        obfuscator_type=$(url_get_query_param "$url" "obfs")
        obfuscator_password=$(url_get_query_param "$url" "obfs-password")
        upload_mbps=$(url_get_query_param "$url" "upmbps")
        download_mbps=$(url_get_query_param "$url" "downmbps")
        sni=$(url_get_query_param "$url" "sni")
        alpn=$(url_get_query_param "$url" "alpn")
        transport=$(url_get_query_param "$url" "type")
        hop_interval=$(url_get_query_param "$url" "hop-interval")

        if [ -z "$password" ] || [ -z "$host" ] || ! _is_valid_port "$port"; then
            log "Invalid Hysteria2 URL: missing required password/host/port fields" "error"
            return 1
        fi
        if [ -z "$sni" ]; then
            sni="$host"
            log "Hysteria2 URL has no sni, using host '$host'" "warn"
        fi
        if [ -z "$alpn" ]; then
            alpn="h3"
            log "Hysteria2 URL has no alpn, using default '$alpn'" "warn"
        fi
        if [ -z "$transport" ]; then
            transport="udp"
            log "Hysteria2 URL has no transport type, using default '$transport'" "warn"
        fi
        if ! _normalize_transport "$transport" > /dev/null; then
            log "Invalid Hysteria2 URL: unsupported transport '$transport'" "error"
            return 1
        fi
        if [ -n "$hop_interval" ]; then
            log "Hysteria2 hop-interval option detected: $hop_interval" "debug"
        fi
        config=$(sing_box_cm_add_hysteria2_outbound "$config" "$tag" "$host" "$port" "$password" "$obfuscator_type" \
            "$obfuscator_password" "$upload_mbps" "$download_mbps" "$transport" "$hop_interval")
        config=$(_add_outbound_security "$config" "$tag" "$url")
        config=$(_add_outbound_transport "$config" "$tag" "$url")
        ;;
    *)
        log "Unsupported proxy scheme '$scheme'" "error"
        return 1
        ;;
    esac

    echo "$config"
}

_add_outbound_security() {
    local config="$1"
    local outbound_tag="$2"
    local url="$3"

    local security scheme
    security=$(url_get_query_param "$url" "security")
    if [ -z "$security" ]; then
        scheme="$(url_get_scheme "$url")"
        if [ "$scheme" = "hysteria2" ] || [ "$scheme" = "hy2" ]; then
            security="tls"
        fi
    fi

    case "$security" in
    tls | reality)
        local sni insecure insecure_bool alpn fingerprint public_key short_id
        sni=$(url_get_query_param "$url" "sni")
        insecure=$(_get_insecure_query_param_from_url "$url")
        insecure_bool=$(_normalize_bool_param_to_singbox "$insecure" "allowInsecure/insecure" "$(url_get_scheme "$url")") || {
            log "Falling back to secure mode because allowInsecure/insecure is invalid" "warn"
            insecure_bool="false"
        }
        alpn=$(comma_string_to_json_array "$(url_get_query_param "$url" "alpn")")
        fingerprint=$(url_get_query_param "$url" "fp")
        public_key=$(url_get_query_param "$url" "pbk")
        short_id=$(url_get_query_param "$url" "sid")

        config=$(
            sing_box_cm_set_tls_for_outbound \
                "$config" \
                "$outbound_tag" \
                "$sni" \
                "$insecure_bool" \
                "$([ "$alpn" == "[]" ] && echo null || echo "$alpn")" \
                "$fingerprint" \
                "$public_key" \
                "$short_id"
        )
        ;;
    none) ;;
    *)
        log "Unknown security '$security' detected." "error"
        ;;
    esac

    echo "$config"
}

_get_insecure_query_param_from_url() {
    local url="$1"

    local insecure
    insecure=$(url_get_query_param "$url" "allowInsecure")
    if [ -z "$insecure" ]; then
        insecure=$(url_get_query_param "$url" "insecure")
    fi

    echo "$insecure"
}

_add_outbound_transport() {
    local config="$1"
    local outbound_tag="$2"
    local url="$3"

    local transport
    transport=$(url_get_query_param "$url" "type")
    transport=$(_normalize_transport "$transport") || return 1
    case "$transport" in
    tcp | raw) ;;
    udp)
        log "Transport '$transport' detected and accepted without extra transport patching" "debug"
        ;;
    ws)
        local ws_path ws_host ws_early_data ws_early_data_header
        ws_path=$(url_get_query_param "$url" "path")
        ws_host=$(url_get_query_param "$url" "host")
        # "ed" param carries max_early_data size; header name differs by client:
        # Xray uses "Sec-WebSocket-Protocol", sing-box default is also that.
        ws_early_data=$(url_get_query_param "$url" "ed")
        ws_early_data_header=$(url_get_query_param "$url" "edHeader")
        [ -z "$ws_early_data_header" ] && [ -n "$ws_early_data" ] && ws_early_data_header="Sec-WebSocket-Protocol"

        config=$(
            sing_box_cm_set_ws_transport_for_outbound "$config" "$outbound_tag" "$ws_path" "$ws_host" "$ws_early_data" "$ws_early_data_header"
        )
        log "WS transport: path='$ws_path' host='$ws_host' early_data='$ws_early_data'" "debug"
        ;;
    grpc)
        local grpc_service_name grpc_authority
        grpc_service_name=$(url_get_query_param "$url" "serviceName")
        # Some clients encode authority/host in "authority" param
        grpc_authority=$(url_get_query_param "$url" "authority")
        [ -z "$grpc_authority" ] && grpc_authority=$(url_get_query_param "$url" "host")

        config=$(
            sing_box_cm_set_grpc_transport_for_outbound "$config" "$outbound_tag" "$grpc_service_name"
        )
        log "gRPC transport: serviceName='$grpc_service_name' authority='$grpc_authority'" "debug"
        ;;
    httpupgrade)
        local hu_path hu_host
        hu_path=$(url_get_query_param "$url" "path")
        hu_host=$(url_get_query_param "$url" "host")

        config=$(
            sing_box_cm_set_httpupgrade_transport_for_outbound "$config" "$outbound_tag" "$hu_path" "$hu_host"
        )
        log "HTTPUpgrade transport: path='$hu_path' host='$hu_host'" "debug"
        ;;
    xhttp)
        local xhttp_path xhttp_host xhttp_mode
        xhttp_path=$(url_get_query_param "$url" "path")
        xhttp_host=$(url_get_query_param "$url" "host")
        xhttp_mode=$(url_get_query_param "$url" "mode")

        config=$(
            sing_box_cm_set_xhttp_transport_for_outbound "$config" "$outbound_tag" "$xhttp_path" "$xhttp_host" "$xhttp_mode"
        )
        log "XHTTP transport: path='$xhttp_path' host='$xhttp_host' mode='$xhttp_mode'" "debug"
        ;;
    http)
        log "Transport '$transport' detected and accepted without extra transport patching" "debug"
        ;;
    *)
        log "Unknown transport '$transport' detected." "error"
        ;;
    esac

    echo "$config"
}

sing_box_cf_add_json_outbound() {
    local config="$1"
    local section="$2"
    local json_outbound="$3"

    local tag
    tag=$(get_outbound_tag_by_section "$section")

    config=$(sing_box_cm_add_raw_outbound "$config" "$tag" "$json_outbound")

    echo "$config"
}

sing_box_cf_add_interface_outbound() {
    local config="$1"
    local section="$2"
    local interface_name="$3"

    local tag
    tag=$(get_outbound_tag_by_section "$section")

    config=$(sing_box_cm_add_interface_outbound "$config" "$tag" "$interface_name")

    echo "$config"
}

sing_box_cf_proxy_domain() {
    local config="$1"
    local inbound="$2"
    local domain="$3"
    local outbound="$4"

    tag="$(gen_id)"
    config=$(sing_box_cm_add_route_rule "$config" "$tag" "$inbound" "$outbound")
    config=$(sing_box_cm_patch_route_rule "$config" "$tag" "domain" "$domain")

    echo "$config"
}

sing_box_cf_override_domain_port() {
    local config="$1"
    local domain="$2"
    local port="$3"

    tag="$(gen_id)"
    config=$(sing_box_cm_add_options_route_rule "$config" "$tag")
    config=$(sing_box_cm_patch_route_rule "$config" "$tag" "domain" "$domain")
    config=$(sing_box_cm_patch_route_rule "$config" "$tag" "override_port" "$port")

    echo "$config"
}

sing_box_cf_add_single_key_reject_rule() {
    local config="$1"
    local inbound="$2"
    local key="$3"
    local value="$4"

    tag="$(gen_id)"
    config=$(sing_box_cm_add_reject_route_rule "$config" "$tag" "$inbound")
    config=$(sing_box_cm_patch_route_rule "$config" "$tag" "$key" "$value")

    echo "$config"
}