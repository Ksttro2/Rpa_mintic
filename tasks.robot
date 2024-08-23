*** Settings ***
Documentation       Robot para mintic.

Library             RPA.Database
Library             RPA.FileSystem
Library             RPA.HTTP
Library             RPA.RobotLogListener
Library             RPA.JSON
Library             RPA.Crypto
Library             Collections
Library             String
Library             DateTime
Library             RPA.Calendar
Library             RPA.Smartsheet

Suite Setup         Inicializar Variables Globales
*** Variables ***
${DB_NAME}                      incoelec_ticketcreador
${DB_USER}                      incoelec_test
${DB_PASSWORD}                  Zte2023*
${DB_HOST}                      100.123.26.141
${SERVICE_MANAGER_URL}          http://172.22.108.160:13090/SM/9/rest/
${SERVICE_MANAGER_USER}         RPACIESM
${SERVICE_MANAGER_PASSWORD}     Control2024**.
@{mac_array}                    MAC_APINT    MAC_APEXT1    MAC_APEXT2


*** Tasks ***
Start
    Get IMs From Database


*** Keywords ***
Get IMs From Database
    Connect To Database    pymysql    ${DB_NAME}    ${DB_USER}    ${DB_PASSWORD}    ${DB_HOST}
    ${ims}=    Query
    ...    SELECT * FROM (SELECT ab.ID_BENEFICIARIO, ab.ID_DE_INCIDENTE, dia.SERVER_AP, dia.MAC_APINT, dia.MAC_APEXT1, dia.MAC_APEXT2, dia.MAC_CD, dia.MAC_BTS, incoelec_customer.mintic_fo_main.FASE_OFICIAL, ab.FECHA_HORA_DE_APERTURA, TIMESTAMPDIFF(DAY, DATE(NOW()), ab.FECHA_HORA_DE_APERTURA) AS días_transcurridos FROM incoelec_mintic.mintic_service_manager_tk_fo_abiertos ab LEFT JOIN incoelec_mintic.mintic_diagnosticador dia ON ab.ID_BENEFICIARIO = dia.IDBEN LEFT JOIN incoelec_customer.mintic_fo_main ON dia.IDBEN = incoelec_customer.mintic_fo_main.ID_Beneficiario WHERE ((PRIORIDAD = '1 - Crítica' AND TITULO LIKE '%CAÍDA TOTAL CENTRO DIGITAL%' AND TITULO NOT LIKE '%#PQR_SD%') OR (PRIORIDAD = '2 - Alta' AND TITULO LIKE '%CAÍDA PARCIAL%' AND TITULO NOT LIKE '%#PQR_SD%') OR (PRIORIDAD = '3 - Media' AND TITULO LIKE '%MEDICIÓN DIRECTA DE VELOCIDAD EFECTIVA DE TRANSMISIÓN DE DATOS - CAIDA%' AND TITULO NOT LIKE '%#PQR_SD%')) AND dia.STATE_APINT = 'online' AND dia.STATE_APEXT1 = 'online' AND ID_DE_INCIDENTE = 'IM2737738' AND dia.STATE_APEXT2 = 'online' AND (LENGTH(ab.fecha_inicio_reloj) <= 35 OR ab.fecha_inicio_reloj IS NULL) AND ((incoelec_customer.mintic_fo_main.FASE_OFICIAL LIKE '%3%' AND TIMESTAMPDIFF(DAY, DATE(NOW()), ab.FECHA_HORA_DE_APERTURA) >= -3) OR (incoelec_customer.mintic_fo_main.FASE_OFICIAL NOT LIKE '%3%' AND TIMESTAMPDIFF(DAY, DATE(NOW()), ab.FECHA_HORA_DE_APERTURA) >= -2))) AS IM_CIERRES
    FOR    ${im}    IN    @{ims}
       log to Console  test${im["ID_DE_INCIDENTE"]}
        Append To File    ${nombre_archivo}    ${im}
        Wait Until Created    ${nombre_archivo}
        Handle IM    ${im}
        Set Variable Global
        Delete txt file    ${im["ID_DE_INCIDENTE"]}
    END
    Disconnect From Database
    Sleep    15m
    Get IMs From Database
    Log info    Waited for 15 minutes

Handle IM
    [Arguments]    ${im}
    ${log_message}=    Catenate    Verifying IM:    ${im['ID_DE_INCIDENTE']}
    ${response}=    Get IM data    ${im}
    ${im_data}=    Set Variable    ${response.json()}
    IF    "${im_data["Incident"]["Status"]}" != "Closed" and "${im_data["Incident"]["Status"]}" != "Resolved"
        ${init_int_serv}=    Run Keyword And Return Status
        ...    Dictionary Should Contain Key
        ...    ${im_data['Incident']}
        ...    IniIntServ
        IF    ${init_int_serv}
            Check Time IM    ${im_data}    ${im}
            IF    '${to_close}' == 'True'
                Log To Console    IM id:${im['ID_DE_INCIDENTE']}
                CLOSE IN SERVICE MANAGER    ${im_data}    ${im}
            END
        ELSE
            DO NOT CLOSE IM    ${im_data}    ${im}    No tiene fecha de inicio de iterrupcion de servicio
        END
    END

Get IM data
    [Arguments]    ${im}
    ${url}=    Catenate    ${SERVICE_MANAGER_URL}incidents/${im['ID_DE_INCIDENTE']}
    ${auth_token}=    Crea Token de Autenticacion    usuario    contraseña
    ${headers}=    Create Dictionary    Authorization=Basic ${auth_token}    Connection=keep-alive
    ${response}=    GET    ${url}    headers=${headers}
    Request Should Be Successful
    Status Should Be    200
    RETURN    ${response}

Check Time IM
    [Arguments]    ${im_data}    ${im}
    ${hora_afectacion_im}=    Set Variable    ${im_data["Incident"]["IniIntServ"]}
    IF    ("${hora_afectacion_im}" == "") or ("${hora_afectacion_im}" == "undefined") or ("${hora_afectacion_im}" == "None")
        Add error in DB    ${im_data}
    ELSE
        CHECK MACS IN CN MAESTRO    ${im_data}    ${im}
    END

Add error in DB
    [Arguments]    ${im_data}
    ${query}=    Catenate
    ...    DELETE FROM incoelec_mintic.mintic_rpa_close_IM WHERE im = '${im_data["Incident"]['IncidentID']}'
    Query    ${query}
    ${update_query}=    Catenate
    ...    INSERT INTO incoelec_mintic.mintic_rpa_close_IM (`im`, `evidencia`, `actividad_realizada`) VALUES ('${im_data["Incident"]['IncidentID']}', 'data_revisada', 'No permitió cierre validar nuevamente')
    Query    ${update_query}
    Delete txt file    ${im_data["Incident"]['IncidentID']}
    Reasignar Variable Global    False

CHECK MACS IN CN MAESTRO
    [Arguments]    ${im_data}    ${im}
    Create txt file    ${im}

    ${Ex_Cont}=    Set Variable    0

    ${index}=    Set Variable    0
    ${mac}=    Set Variable    ""
    ${url_request}=    Set Variable    ""
    ${token}=    Set Variable    ""
    ${url}=    Set Variable    ""
    ${is_online}=    Set Variable    False
    FOR    ${mac_name}    IN    @{mac_array}
        ${get_tokens_data_query}=    Query    SELECT cn, token FROM incoelec_mintic.mintic_cnmaestro_token
        ${get_tokens_data}=    Create JSON List    ${get_tokens_data_query}
        ${mac}=    Set Variable    ${im['${mac_name}']}
        IF    "${im["${mac_name}"]}" == "" or "${im["${mac_name}"]}" == "undefined" or "${im["${mac_name}"]}" == "None"
            ${Ex_Cont}=    Evaluate    ${Ex_Cont} + 1
        ELSE
            IF    '${im["SERVER_AP"]}' == 'cn1'
                ${token}=    Set Variable    ${get_tokens_data["CN1"]}
                ${url}=    Set Variable    https://100.123.26.224/api/v2/devices/
            END
            IF    '${im["SERVER_AP"]}' == 'cn2'
                ${token}=    Set Variable    ${get_tokens_data["CN2"]}
                ${url}=    Set Variable    https://100.123.26.252/api/v2/devices/
            END

            ${url_request}=    Set Variable    ${url}${mac}
            ${response_cn}=    Connect To CNMaestro    ${url_request}    ${token}
            IF    '${response_cn.json()['data'][0]['status']}' == 'online'
                ${is_online}=    Set Variable    True
                IF    ${response_cn.json()['data'][0]['status_time']} < 340
                    DO NOT CLOSE IM    ${im_data}    ${im}    No lleva al menos una hora online
                ELSE
                    Connect To CNMaestro Events
                    ...    ${url_request}
                    ...    ${token}
                    ...    ${im_data}
                    ...    ${im}
                    ...    ${mac}
                END
            END
        END
        IF    '${to_close}' == 'False'    BREAK

        ${index}=    Evaluate    ${index} + 1
    END

    IF    '${is_online}' == 'True' and '${to_close}' == 'True'
        ${value}=    Comparar Fechas con Tolerancia de 5 Minutos    ${service_date}    ${date_up}
        IF    ${value} == True
            Get Data to send in SM    ${im_data}    ${im}    CD
        ELSE
            ${mac_bts}=    Set Variable    ${im['MAC_BTS']}
            IF    "${mac_bts}" == "" or "${mac_bts}" == "undefined" or "${mac_bts}" == "None"
                IF    "${im_data["Incident"]["UserPriority"]}" == "2"
                    Get Data to send in SM    ${im_data}    ${im}    AUTO2
                ELSE
                    Get Data to send in SM    ${im_data}    ${im}    AUTO
                END
            ELSE
                CHECK RADIO    ${im_data}    ${im}    ${mac_bts}
            END
        END
    ELSE
        DO NOT CLOSE IM    ${im_data}    ${im}    Sitio sin conectividad de APs
    END

CHECK RADIO
    [Arguments]    ${im_data}    ${im}    ${mac}
    ${get_tokens_data_query}=    Query    SELECT cn, token FROM incoelec_mintic.mintic_cnmaestro_token
    ${get_tokens_data}=    Create JSON List    ${get_tokens_data_query}
    ${token}=    Set Variable    ${get_tokens_data["RS1"]}
    ${url}=    Set Variable    https://100.123.26.246/api/v2/devices/
    ${url_request}=    Set Variable    ${url}${mac}
    ${response_cn}=    Connect To CNMaestro    ${url_request}    ${token}
    IF    '${response_cn.json()['data'][0]['status']}' == 'online'
        ${is_online}=    Set Variable    True
        IF    ${response_cn.json()['data'][0]['status_time']} < 340
            DO NOT CLOSE IM    ${im_data}    ${im}    BTS: No lleva al menos una hora online
        ELSE
            Connect To CNMaestro Events
            ...    ${url_request}
            ...    ${token}
            ...    ${im_data}
            ...    ${im}
            ...    ${mac}

            ${value}=    Comparar Fechas con Tolerancia de 5 Minutos    ${service_date}    ${date_up}
            IF    ${value} == True
                Get Data to send in SM    ${im_data}    ${im}    BTS
            ELSE
                Get Data to send in SM    ${im_data}    ${im}    TX
            END
        END
    END

Create txt file
    [Arguments]    ${im}
    ${nombre_archivo}=    Catenate    ./${im["ID_DE_INCIDENTE"]}-adjunto.txt
    Create file    ${nombre_archivo}    content=IM,ID_BEN,MAC,Estado,Hora_revision
    ...    overwrite=${True}
    Wait until created    ${nombre_archivo}

Delete txt file
    [Arguments]    ${im_id}
    ${nombre_archivo}=    Catenate    ./${im_id}-adjunto.txt
    Remove file    ${nombre_archivo}

Log info
    [Arguments]    ${info}
    Log    ${info}

Connect To CNMaestro
    [Arguments]    ${url_request}    ${token}
    ${headers}=    Create Dictionary
    ...    Authorization=Bearer ${token}
    ${response}=    GET    ${url_request}    headers=${headers}    verify=${False}
    Request Should Be Successful
    Status Should Be    200
    Calcular Fecha desde Segundos    ${response.json()['data'][0]['status_time']}
    RETURN    ${response}

Connect To CNMaestro Events    # https://prycnmap1.claro.net.co/api/v2/devices/BC:E6:7C:E9:CE:76/events?fields=name,source,time_raised&offset=0&code=STATUS_UP&start_time=2019-02-01T05:35:53+00:00
    [Arguments]
    ...    ${url_request}
    ...    ${token}
    ...    ${im_data}
    ...    ${im}
    ...    ${mac}
    ${headers}=    Create Dictionary    Authorization=Bearer ${token}    Connection=keep-alive
    ${url_request_events}=    Catenate
    ...    ${url_request}/events?fields=name,source,time_raised&offset=0&code=STATUS_UP&start_time=${im_data["Incident"]["IniIntServ"]}

    ${response}=    GET
    ...    ${url_request_events}
    ...    headers=${headers}
    ...    verify=${False}
    Request Should Be Successful
    Status Should Be    200
    ${response_json}=    Set Variable    ${response.json()}

    IF    ${response_json['paging']['total']} > 100
        ${offset}=    Evaluate    ${response_json['paging']['total']} - 1
        ${response_json}=    CN Maestro Consulta    ${url_request}    ${token}    ${im_data}    ${offset}
    END

    ${data}=    Get length    ${response_json['data']}

    IF    ${data} > 0
        Get Max date    ${response_json['data'][-1]['time_raised']}
        Feed Evidence    ${im}    ${response_json}    ${mac}
    ELSE
        DO NOT CLOSE IM
        ...    ${im_data}
        ...    ${im}
        ...    Sin cierre por CN Maestro Server AP: ${im['SERVER_AP']}
    END

CN Maestro Consulta
    [Arguments]
    ...    ${url_request}
    ...    ${token}
    ...    ${im_data}
    ...    ${offset}
    ${headers}=    Create Dictionary    Authorization=Bearer ${token}    Connection=keep-alive
    ${url_request_events}=    Catenate
    ...    ${url_request}/events?fields=name,source,time_raised&offset=${offset}&code=STATUS_UP&start_time=${im_data["Incident"]["IniIntServ"]}

    ${response}=    GET
    ...    ${url_request_events}
    ...    headers=${headers}
    ...    verify=${False}
    Request Should Be Successful
    Status Should Be    200
    ${response_json}=    Set Variable    ${response.json()}
    RETURN    ${response_json}

Feed Evidence
    [Arguments]    ${im}    ${response_json}    ${mac}
    ${last_element}=    Set Variable    ${response_json['data'][-1]}
    ${nombre_archivo}=    Catenate    ./${im['ID_DE_INCIDENTE']}-adjunto.txt
    Append To File    ${nombre_archivo}    ${\n}
    ${line}=    Catenate
    ...    ${im['ID_DE_INCIDENTE']},${im['ID_BENEFICIARIO']},${mac},online,${last_element['time_raised']}
    Append To File    ${nombre_archivo}    ${line}

Crea Token de Autenticacion
    [Arguments]    ${usuario}    ${contrasenia}
    ${auth_string}=    Catenate    ${usuario}    :    ${contrasenia}
    ${encoded_string}=    Set Variable  UlBBQ0lFU006Q29udHJvbDIwMjQqKi4=    ## Base64 Encode    ${auth_string}
    RETURN    ${encoded_string}

Create JSON List
    [Arguments]    ${get_tokens_data}
    ${json_dict}=    Create Dictionary
    FOR    ${item}    IN    @{get_tokens_data}
        ${cn}=    Get From Dictionary    ${item}    cn
        ${token}=    Get From Dictionary    ${item}    token
        Set To Dictionary    ${json_dict}    ${cn}    ${token}
    END
    RETURN    ${json_dict}

CLOSE IN SERVICE MANAGER
    [Arguments]    ${im_data}    ${im}
    ${fecha_actual}=    Get Current Date    result_format=%Y-%m-%dT%H:%M:%S%z
    ${fecha_im_data}=    Set Variable    ${im_data["Incident"]["IniIntServ"]}

    ${fecha_actual_obj}=    Convert Date    ${fecha_actual}    result_format=%Y-%m-%dT%H:%M:%S%z
    ${fecha_im_data_obj}=    Convert Date    ${fecha_im_data}    result_format=%Y-%m-%dT%H:%M:%S%z

    ${diff}=    Subtract Date From Date    ${fecha_actual}    ${fecha_im_data}

    IF    ${diff} <= 432000 and '${im_data["Incident"]["Status"]}' != 'Closed'    # 3 dias en segundos (72)
        # CLOSE IMS    ${im_data}    ${im}
        CLOSE IM    ${im_data}    ${im}
    ELSE IF    ${diff} <= 345600    # Menor o igual a 96 horas 345600, 446400
        ${response_check}=    IM sin desplazamiento a campo    ${im['ID_BENEFICIARIO']}
        ${response_check_len}=    Get Length    ${response_check}

        IF    ${response_check_len} > 0
            ${message}=    Set Variable    ${justificacion_message} Mayor a 72 horas
            DO NOT CLOSE IM    ${im_data}    ${im}    ${message}
        ELSE
            # DO NOT CLOSE IM    ${im_data}    ${im}    mayor a 76 horas a cerrar  guardar los ims
            CLOSE IM    ${im_data}    ${im}
        END
    ELSE
        ${message}=    Set Variable    ${justificacion_message} Mayor a 96 horas
        DO NOT CLOSE IM    ${im_data}    ${im}    ${message}
    END

CLOSE IM
    [Arguments]    ${im_data}    ${im}
    # Create txt file with responses    ${im}
    ${working_data}=    Create Dictionary
    ...    Status=Work In Progress
    UPDATE IM    ${im_data}    ${im}    ${working_data}
    ${response_pdr}=    Conexion PDR    ${im}
    CREATE PDR    ${im_data}    ${im}    ${response_pdr}
    ${FinIntServ_utc}=    Add Time To Date    ${date_up}    5h
    ${FinIntServ_utc}=    Convert Date    ${FinIntServ_utc}    result_format=%Y-%m-%dT%H:%M:%S%z
    ${sol_msg}=    Create List    ${note_message}
    ${journal_msg}=    Create List    Cierre IM    ${justificacion_message}    ${note_message}
    ${resolved_data}=    Create Dictionary
    ...    Status=Resolved
    ...    ClosureCode=Resolved Successfully
    ...    FinIntServ=${FinIntServ_utc}
    ...    KMDoc=${km_doc}
    ...    Solution=${sol_msg}
    ...    JournalUpdates=${journal_msg}
    ...    Responsabilidad=Responsabilidad Cliente
    Upload File    ${im_data}    ${im}
    UPDATE IM    ${im_data}    ${im}    ${resolved_data}
    DO NOT CLOSE IM    ${im_data}    ${im}    Cerrado: ${justificacion_message}

CLOSE IMS
    [Arguments]    ${im_data}    ${im}
    
    ${nombre_archivo}=    Catenate    ./errores.txt
    ${content}=    Catenate    SEPARATOR=\n   ${im['ID_DE_INCIDENTE']}   \n
    
    # Append the content to the existing file
    Append To File    ${nombre_archivo}    ${content}
    
    # Wait until the file is updated
    Wait Until Created    ${nombre_archivo}

Conexion PDR
    [Arguments]    ${im}
    ${url}=    Catenate    ${SERVICE_MANAGER_URL}IMPDR/${im['ID_DE_INCIDENTE']}
    ${auth_token}=    Crea Token de Autenticacion    usuario    contraseña
    ${headers}=    Create Dictionary    Authorization=Basic ${auth_token}    Connection=keep-alive
    ${response}=    GET    ${url}    headers=${headers}
    Request Should Be Successful
    Status Should Be    200
    RETURN    ${response.json()}

Append To List Elements
    [Arguments]    ${list}    ${element}
    ${new_list}=    Create List
    FOR    ${item}    IN    @{list}
        Append To List    ${new_list}    ${item}
    END

    IF    ${pdr} == True    Append To List    ${new_list}    ${element}
    RETURN    ${new_list}

Append To List Dates
    [Arguments]    ${list}    ${element}    ${type}
    ${new_list}=    Create List
    ${fecha_actual}=    Get Current Date    result_format=%Y-%m-%dT%H:%M:%S%z
    ${fecha_actual_utc}=    Add Time To Date    ${fecha_actual}    5h
    ${fecha_actual_utc}=    Convert Date    ${fecha_actual_utc}    result_format=%Y-%m-%dT%H:%M:%S%z

    FOR    ${item}    IN    @{list}
        ${item_date}=    Subtract Date From Date    ${item}    ${fecha_actual_utc}
        IF    ${item_date} >= 0
            ${new_date}=    Subtract Time From Date    ${date_up}    1s
            ${new_date_utc}=    Add Time To Date    ${new_date}    5h
            ${new_date_utc}=    Convert Date    ${new_date_utc}    result_format=%Y-%m-%dT%H:%M:%S%z
            disable PDR
            Append To List    ${new_list}    ${new_date_utc}
        ELSE
            ${new_dup}=    Add Time To Date    ${date_up}    5h
            ${item_up}=    Subtract Date From Date    ${item}    ${new_dup}
            ${new_date_op}=    Subtract Time From Date    ${date_up}    3s
            ${new_date_utc_op}=    Add Time To Date    ${new_date_op}    5h
            ${new_date_utc_op}=    Convert Date    ${new_date_utc_op}    result_format=%Y-%m-%dT%H:%M:%S%z
            IF    ${item_up} >= 0
                Append To List    ${new_list}    ${new_date_utc_op}
            ELSE
                IF    ${pdr} == False and ${type} == 'FIN'
                    Append To List    ${new_list}    ${new_date_utc_op}
                ELSE
                    Append To List    ${new_list}    ${item}
                END
            END
        END
    END
    IF    ${pdr} == True    Append To List    ${new_list}    ${element}
    RETURN    ${new_list}

CREATE PDR
    [Arguments]    ${im_data}    ${im}    ${response}
    ${new_dup}=    Add Time To Date    ${date_up}    5h
    ${len_inidate}=    Get length    ${response['IM']['FechaIniReloj']}
    IF    ${len_inidate} == 2
        ${last_date_seg_pdr}=    Set Variable    ${response['IM']['FechaIniReloj'][-1]}
        ${item_up_seg_pdr}=    Subtract Date From Date    ${last_date_seg_pdr}    ${new_dup}
        IF    ${item_up_seg_pdr} < 0
            ${Aux_FechaIniReloj_list}=    Create List
            ${Aux_FechaFinReloj_list}=    Create List
            ${fecha_fin_list}=    Append To List Dates    ${Aux_FechaFinReloj_list}    ${response['IM']['FechaFinReloj'][0]}    'FIN'
            Log To Console    ${fecha_fin_list}
            ${fecha_ini_list}=    Append To List Dates    ${Aux_FechaIniReloj_list}    ${response['IM']['FechaIniReloj'][0]}    'INI'
        ELSE
            ${fecha_fin_list}=    Set Variable    ${response['IM']['FechaFinReloj']}
            ${fecha_ini_list}=    Set Variable    ${response['IM']['FechaIniReloj']}
        END
    END
    # estamos aqui
    Log To Console    ${new_dup}
    Log To Console    ${fecha_fin_list}
    Log To Console    ${fecha_ini_list}
    ${total_pdr_exist}=    Run Keyword And Return Status
    ...    Dictionary Should Contain Key
    ...    ${response['IM']}
    ...    FechaIniReloj

    IF    ${total_pdr_exist} != True
        ${FechaIniReloj}=    Add 1 minute to Date    ${im_data["Incident"]["IniIntServ"]}
        ${FechaIniReloj_list}=    Create List
        ${FechaFinReloj_list}=    Create List
        Log To Console    totaltrue
    ELSE
        Log To Console    totalfalse
        ${FechaIniReloj_list}=    Set Variable    ${fecha_ini_list}
        ${FechaFinReloj_list}=    Set Variable    ${fecha_fin_list}
        ${last_date}=    Set Variable    ${fecha_fin_list[-1]}
        ${item_up}=    Subtract Date From Date    ${last_date}    ${new_dup}
        IF    ${item_up} >= 0
            ${new_date_op}=    Subtract Time From Date    ${date_up}    3s
            ${new_date_utc_op}=    Add Time To Date    ${new_date_op}    5h
            ${new_date_utc_op}=    Convert Date    ${new_date_utc_op}    result_format=%Y-%m-%dT%H:%M:%S%z
            ${FechaIniReloj}=    Add 1 minute to Date    ${new_date_utc_op}
        ELSE
            ${FechaIniReloj}=    Add 1 minute to Date    ${last_date}
        END
    END

    Log To Console    saliototal
    ${justificacion_exists}=    Run Keyword And Return Status
    ...    Dictionary Should Contain Key
    ...    ${response['IM']}
    ...    Justificacion
    ${motivo_exists}=    Run Keyword And Return Status    Dictionary Should Contain Key    ${response['IM']}    Motivo

    IF    ${justificacion_exists}    # Check if the key exists in the dictionary
        ${justificacion_list}=    Set Variable    ${response['IM']['Justificacion']}
        Log To Console     ${justificacion_list}
    ELSE
        ${justificacion_list}=    Create List
        Log To Console    salida2
    END

    Log To Console    salidatotal

    IF    ${motivo_exists}    # Check if the key exists in the dictionary
        ${motivo_list}=    Set Variable    ${response['IM']['Motivo']}
        Check If Last Motivo is Same    ${response['IM']['Motivo'][-1]}  ${im}
    ELSE
        ${motivo_list}=    Create List    ${motivo_message}
    END

    ${date_up_utc}=    Add Time To Date    ${date_up}    5h
    ${date_up_utc}=    Convert Date    ${date_up_utc}    result_format=%Y-%m-%dT%H:%M:%S%z
    ${FechaFinReloj}=    Substract 1 minute to Date    ${date_up_utc}
    Log To Console    ${FechaFinReloj}
    ${fecha_fin_list}=    Append To List Dates    ${FechaFinReloj_list}    ${FechaFinReloj}    'FIN'
    ${fecha_ini_list}=    Append To List Dates    ${FechaIniReloj_list}    ${FechaIniReloj}    'INI'

    ${adjusted_motivo_list}    ${adjusted_justificacion_list}=    Adjust Lists Size
    ...    ${motivo_list}
    ...    ${justificacion_list}

    ${justificacion_list}=    Append To List Elements
    ...    ${adjusted_justificacion_list}
    ...    ${justificacion_message}

    ${motivo_list}=    Append To List Elements    ${adjusted_motivo_list}    ${motivo_message}

    ${data_to_send}=    Create Dictionary
    ...    FechaFinReloj=${fecha_fin_list}
    ...    FechaIniReloj=${fecha_ini_list}
    ...    Justificacion=${justificacion_list}
    ...    Motivo=${motivo_list}
    
    ${nombre_archivo}=    Catenate    ./errores_data_to_send.txt
    ${content}=    Catenate    SEPARATOR=\n   ${im['ID_DE_INCIDENTE']}   \n   ${data_to_send}
    
    # Append the content to the existing file
    Append To File    ${nombre_archivo}    ${content}
    
    # Wait until the file is updated
    Wait Until Created    ${nombre_archivo}

    # Construir la URL
    ${url}=    Catenate    ${SERVICE_MANAGER_URL}IMPDR/${im['ID_DE_INCIDENTE']}

    # Crear el cuerpo de la solicitud
    ${body}=    Create Dictionary    IM=${data_to_send}

    # Crear el token de autenticación
    ${auth_token}=    Crea Token de Autenticacion    usuario    contraseña
    ${headers}=    Create Dictionary    Authorization=Basic ${auth_token}    Connection=keep-alive
    ${response_put}=    PUT    ${url}    headers=${headers}    json=${body}
    # Log To Console    ${response_put.text}
    # ${content}=    Catenate    SEPARATOR=\n   ${im['ID_DE_INCIDENTE']}   ${response_put.json()}
    # Append To File    ${nombre_archivo}    ${content}
    Request Should Be Successful
    Status Should Be    200

Get Data to send in SM
    [Arguments]    ${im_data}    ${im}    ${type}

    IF    '${type}' == 'BTS'
        ${note}=    Catenate
        ...    M7k - ENERGIA BTS FALLA ELECTRICA RED COMERCIAL
        ...    ${\n}
        ...    ${\n}
        ...    Causal Falla: Falla de energía ZONA
        ...    ${\n}
        ...    Solución Falla: Retorno de AC comercial
        ...    ${\n}
        ...    Se realiza validación remota donde se evidencia falla de energía por medio de un incidente presentado por la móvil, lo cual no permite el tráfico de conectividad al CD, se evidencia retorno de AC comercial quedando el CD en estado Operativo.

        Update Variable Global Message
        ...    Atribuible Terceros - Falla Energía Comercial Zona
        ...    Falla Energía Comercial Zona
        ...    KM11384
        ...    ${note}
    ELSE IF    '${type}' == 'CD'
        ${note}=    Catenate
        ...    MINTIC - SOLUCIÓN INCIDENTE
        ...    ${\n}
        ...    ${\n}
        ...    Causal Falla: Falla de energía (ZONA/CD)
        ...    ${\n}
        ...    Solución Falla: Retorno de AC comercial
        ...    ${\n}
        ...    Se realiza validación remota donde se evidencio falla de energía Lo cual no permite el tráfico de conectividad al CD, se evidencia retorno de AC comercial quedando el servicio del CD con estado Operativo. Se observa Uptime del CPE y del cnMaestro a la misma hora, por tanto se atribuye a falla de energía.

        Update Variable Global Message
        ...    Atribuible Terceros - Falla Energía Eléctrica en CD
        ...    Falla de energía en CD
        ...    KM11380
        ...    ${note}
    ELSE IF    '${type}' == 'AUTO'
        ${note}=    Catenate
        ...    MINTIC - SOLUCIÓN INCIDENTE REMOTO
        ...    ${\n}
        ...    ${\n}
        ...    Causal Falla: Indeterminada
        ...    ${\n}
        ...    Solución Falla: Servicio se restablece sin intervención
        ...    ${\n}
        ...    Se realiza validación remota donde se evidencia Falla Indeterminada. Lo cual no permite el tráfico de conectividad al CD, para ello, se restablece Servicio sin intervención quedando el servicio del CD con estado OPERATIVO.
        Update Variable Global Message
        ...    Atribuible Terceros - Sin contacto con CD
        ...    Atribuible Terceros - Sin contacto con CD
        ...    KM10465
        ...    ${note}
    ELSE IF    '${type}' == 'AUTO2'
        ${note}=    Catenate
        ...    MINTIC - SOLUCIÓN INCIDENTE REMOTO
        ...    ${\n}
        ...    ${\n}
        ...    Causal Falla: AP desconfigurada/bloqueada
        ...    ${\n}
        ...    Solución Falla: Retorno del servicio por validación remota en la Mikrotik
        ...    ${\n}
        ...    Se realiza validación remota donde se evidencia falla del servicio debido a que la AP relacionada se encontraba deshabilitada en la interfaz, se observa servicio operativo después de la validación.
        Update Variable Global Message
        ...    Atribuible Terceros - Sin contacto con CD
        ...    Atribuible Terceros - Sin contacto con CD
        ...    KM11387
        ...    ${note}
    ELSE IF    '${type}' == 'TX'
        ${note}=    Catenate
        ...    MINTIC - SOLUCIÓN INCIDENTE REMOTO
        ...    ${\n}
        ...    ${\n}
        ...    Causal Falla: TX RUTA- RADIO Trasmisión Daño/Bloqueo/apagado
        ...    ${\n}
        ...    Solución Falla: Se reporta INC por parte de la móvil con solución.
        ...    ${\n}
        ...    Se evidencia las AP's del CnMaestro online, Se observa Dashboard del CnMaestro se encuentra online y operativo, se realiza ping exitoso con la terminal Hughes Net, se presenta afectación por TX RUTA- RADIO Trasmisión Daño/Bloqueo/apagado, Se adjunta evidencia de operatividad.
        Update Variable Global Message
        ...    Atribuible Terceros - Sin contacto con CD
        ...    Atribuible Terceros - Sin contacto con CD
        ...    KM11417
        ...    ${note}
    END

UPDATE IM
    [Arguments]    ${im_data}    ${im}    ${data}
    ${data_json}=    Create Dictionary    Incident=${data}
    ${url}=    Catenate    ${SERVICE_MANAGER_URL}incidents/${im['ID_DE_INCIDENTE']}
    ${auth_token}=    Crea Token de Autenticacion    usuario    contraseña
    ${headers}=    Create Dictionary    Authorization=Basic ${auth_token}    Connection=keep-alive
    ${response}=    PUT    ${url}    headers=${headers}    json=${data_json}
    Request Should Be Successful
    Status Should Be    200

Upload File
    [Arguments]    ${im_data}    ${im}
    ${url}=    Catenate    ${SERVICE_MANAGER_URL}incidents/${im['ID_DE_INCIDENTE']}/attachments
    ${auth_token}=    Crea Token de Autenticacion    usuario    contraseña

    ${headers}=    Create Dictionary
    ...    Authorization=Basic ${auth_token}
    ...    Connection=keep-alive
    ...    Content-Type=application/txt
    ...    Content-Disposition=attachment; filename=${im['ID_DE_INCIDENTE']}-adjunto.txt
    ${file_path}=    Catenate    ./${im['ID_DE_INCIDENTE']}-adjunto.txt
    ${file_content}=    Read File    ${file_path}

    ${files}=    Create Dictionary    file=@${file_content}
    ${response}=    POST    ${url}    headers=${headers}    files=${files}
    Request Should Be Successful
    Status Should Be    200
    RETURN    ${response}

DO NOT CLOSE IM
    [Arguments]    ${im_data}    ${im}    ${message}
    ${fecha_actual}=    Get Current Date    result_format=%Y-%m-%dT%H:%M:%S%z
    ${fecha_im_data}=    Set Variable    ${im_data["Incident"]["IniIntServ"]}

    ${diff}=    Subtract Date From Date    ${fecha_actual}    ${fecha_im_data}

    IF    ${diff} <= 259200    # 3 dias en segundos (72)
        ${horas_total}=    Set Variable    Menor a 72 horas
    ELSE IF    ${diff} <= 345600
        ${horas_total}=    Set Variable    Entre 72 horas y 96 horas
    ELSE
        ${horas_total}=    Set Variable    Mayor a 96 horas
    END

    ${final_msg}=    Catenate
    ...    ${message}
    ...    ID_BEN: ${im['ID_BENEFICIARIO']} Prioridad: ${im_data["Incident"]["UserPriority"]} ${horas_total}
    ${query}=    Catenate
    ...    DELETE FROM incoelec_mintic.mintic_rpa_close_IM WHERE im = '${im_data["Incident"]['IncidentID']}'
    Query    ${query}
    ${update_query}=    Catenate
    ...    INSERT INTO incoelec_mintic.mintic_rpa_close_IM (`im`, `evidencia`, `actividad_realizada`) VALUES ('${im_data["Incident"]["IncidentID"]}', 'data_revisada', '${final_msg}')
    Query    ${update_query}
    Delete txt file    ${im_data["Incident"]['IncidentID']}
    Reasignar Variable Global    False

Inicializar Variables Globales
    Set Suite Variable    ${to_close}    True
    Set Suite Variable    ${Cont_online}    0
    Set Suite Variable    ${date_up}    1900-01-01T00:00:00+00:00
    Set Suite Variable    ${justificacion_message}    ""
    Set Suite Variable    ${motivo_message}    ""
    Set Suite Variable    ${km_doc}    ""
    Set Suite Variable    ${note_message}    ""
    Set Suite Variable    ${service_date}    1900-01-01T00:00:00+00:00
    Set Suite Variable    ${pdr}    ${True}

Reasignar Variable Global
    [Arguments]    ${nuevo_valor}
    Set Suite Variable    ${to_close}    ${nuevo_valor}

Update Variable Global Message
    [Arguments]    ${motivo}    ${justificacion}    ${km}    ${note}
    Set Suite Variable    ${motivo_message}    ${motivo}
    Set Suite Variable    ${justificacion_message}    ${justificacion}
    Set Suite Variable    ${km_doc}    ${km}
    Set Suite Variable    ${note_message}    ${note}

Incrementar contador online
    ${nuevo_valor}=    Evaluate    ${Cont_online} + 1
    Set Suite Variable    ${Cont_online}    ${nuevo_valor}

Set Variable Global
    Set Suite Variable    ${Cont_online}    ${0}
    Set Suite Variable    ${to_close}    ${True}
    Set Suite Variable    ${date_up}    1900-01-01T00:00:00+00:00
    Set Suite Variable    ${pdr}    ${True}

disable PDR
    Set Suite Variable    ${pdr}    ${False}

Get Max date
    [Arguments]    ${date}
    IF    '${date_up}' < '${date}'
        Set Suite Variable    ${date_up}    ${date}
    END

Add 1 minute to Date
    [Arguments]    ${date}
    ${date}=    Add Time To Date    ${date}    1s
    ${date}=    Convert Date    ${date}    result_format=%Y-%m-%dT%H:%M:%S%z
    RETURN    ${date}

Substract 1 minute to Date
    [Arguments]    ${date}
    ${date}=    Subtract Time From Date    ${date}    5s
    ${date}=    Convert Date    ${date}    result_format=%Y-%m-%dT%H:%M:%S%z
    RETURN    ${date}

Comparar Fechas con Tolerancia de 5 Minutos
    [Arguments]    ${fecha_actual}    ${fecha_status_up}

    ${fecha_actual_obj}=    Convert Date    ${fecha_actual}    result_format=%Y-%m-%dT%H:%M:%S%z
    ${fecha_status_up_obj}=    Convert Date    ${fecha_status_up}    result_format=%Y-%m-%dT%H:%M:%S%z

    ${diferencia_segundos}=    Subtract Date from Date
    ...    ${fecha_status_up_obj}
    ...    ${fecha_actual_obj}
    IF    ${diferencia_segundos} <= 900    # 900 segundos = 15 minutos
        RETURN    True
    ELSE
        RETURN    False
    END

Check If Last Motivo is Same
    [Arguments]    ${motivo}    ${im}
    ${motivo}=    Catenate    ${motivo}
    ${motivo_message}=    Catenate    ${motivo_message}
    IF    '${motivo}' == '${motivo_message}'    disable PDR
    IF    '${motivo}' == 'Continuidad servicio - Instalaciones no disponibles - Fuera de horario'
        Log To Console    Continuidad de servicio
        # disable PDR
        ${nombre_archivo}=    Catenate    ./im-motivo.txt
        Append To File    ${nombre_archivo}    ${\n}
        ${line}=    Catenate   ${im['ID_DE_INCIDENTE']}
        Append To File    ${nombre_archivo}    ${line}
    END
Adjust Lists Size
    [Arguments]    ${list1}    ${list2}
    ${list1_length}=    Get Length    ${list1}
    ${list2_length}=    Get Length    ${list2}

    ${max_length}=    Evaluate    max(${list1_length}, ${list2_length})
    ${new_list1}=    Create List
    ${new_list2}=    Create List
    FOR    ${index}    IN RANGE    ${max_length}
        IF    ${index} < ${list1_length}
            ${element1}=    Set Variable    ${list1[${index}]}
        ELSE IF    ${list1_length} > 0
            ${element1}=    Set Variable    ${list1[-1]}
        ELSE
            ${element1}=    Set Variable    ${list2[-1]}
        END

        IF    ${index} < ${list2_length}
            ${element2}=    Set Variable    ${list2[${index}]}
        ELSE IF    ${list2_length} > 0
            ${element2}=    Set Variable    ${list2[-1]}
        ELSE
            ${element2}=    Set Variable    ${list1[-1]}
        END

        Append To List    ${new_list1}    ${element1}
        Append To List    ${new_list2}    ${element2}
    END
    RETURN    ${new_list1}    ${new_list2}

Calcular Fecha desde Segundos
    [Arguments]    ${segundos_operativo}

    ${fecha_actual}=    Get Current Date    result_format=%Y-%m-%dT%H:%M:%S%z
    ${nueva_fecha_obj}=    Subtract Time From Date    ${fecha_actual}    ${segundos_operativo} seconds
    Set Suite Variable    ${service_date}    ${nueva_fecha_obj}

IM sin desplazamiento a campo
    [Arguments]    ${id_ben}
    ${query}=    Catenate
    ...    SELECT
    ...    *
    ...    FROM incoelec_ticketcreador.bitacora_minti
    ...    WHERE id_ben = '${id_ben}' AND DATE(fecha) = CURDATE()
    ...    ORDER BY fecha DESC
    ...    LIMIT 1
    ${result}=    Query    ${query}
    RETURN    ${result}
