# 全局配置参数
$USER_FILTER = @() # 要过滤的用户列表，空数组表示不过滤，示例 '@("uname1", "uname2")'
$MAX_LENGTH = 30   # 最大显示条目数
$MAX_DAY = 30      # 显示日期范围

# 设置时间范围
$startTime = (Get-Date).AddDays(-$MAX_DAY).Date

# 常见登录失败原因映射
$failureReasonMap = @{
    '%%2305' = '指定的用户帐户已过期'
    '%%2309' = '指定帐户的密码已过期'
    '%%2310' = '帐户当前已禁用'
    '%%2311' = '帐户登录时间限制违规'
    '%%2312' = '用户不允许在此计算机上登录'
    '%%2313' = '用户名或密码错误'
}

# 获取RDP登录成功事件（事件ID 1149）
$successEvents = Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'
    ID        = 1149
    StartTime = $startTime
} -ErrorAction SilentlyContinue

# 解析显示成功事件
$successEvents | ForEach-Object {
    # 转化为完整的XML文档对象
    $xmlDoc = New-Object System.Xml.XmlDocument
    $xmlDoc.LoadXml($_.ToXml())
    
    # 命名空间管理器
    $nsManager = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
    $nsManager.AddNamespace("evt", $xmlDoc.DocumentElement.NamespaceURI)
    $nsManager.AddNamespace("data", "Event_NS")

    # 修正后XPath查询
    $userData = $xmlDoc.SelectSingleNode(
        "//evt:UserData/data:EventXML", 
        $nsManager
    )

    [PSCustomObject]@{
        TimeCreated = $_.TimeCreated
        User        = if ($userData.Param1) { $userData.Param1 } else { "-" }
        Domain      = if ($userData.Param2) { $userData.Param2 } else { "-" }
        SourceIP    = if ($userData.Param3) { $userData.Param3 } else { "-" }
    }
} | Where-Object {
    # 过滤器
    $USER_FILTER.Count -eq 0 -or $USER_FILTER -contains $_.User
} | Select-Object -First $MAX_LENGTH | Sort-Object TimeCreated |
Format-Table -AutoSize -Property TimeCreated, User, Domain, SourceIP

Write-Host "`n=== 失败日志 ===`n"

# 取得登录失败事件（事件ID 4625）
$failureEvents = Get-WinEvent -FilterHashtable @{
    LogName   = 'Security'
    ID        = 4625
    StartTime = $startTime
} -ErrorAction SilentlyContinue

# 解析失败事件
$failureEvents | ForEach-Object {
    $xml = [xml]$_.ToXml()
    $data = @{}
    $xml.Event.EventData.Data | ForEach-Object { $data[$_.Name] = $_.'#text' }
    
    [PSCustomObject]@{
        TimeCreated     = $_.TimeCreated
        AccountName     = if ($data['TargetUserName']) { $data['TargetUserName'] } else { "-" }
        AccountDomain   = if ($data['TargetDomainName']) { $data['TargetDomainName'] } else { "-" }
        FailureReason   = if ($data['FailureReason']) {
            if ($failureReasonMap.ContainsKey($data['FailureReason'])) {
                $failureReasonMap[$data['FailureReason']]
            } else {
                $data['FailureReason']
            }
        } else { "-" }
        SourceIPAddress = if ($data['IpAddress']) { $data['IpAddress'] } else { "-" }
        SourcePort      = if ($data['IpPort']) { $data['IpPort'] } else { "-" }
    }
} | Where-Object {
    # 过滤和排序
    $USER_FILTER.Count -eq 0 -or $USER_FILTER -contains $_.AccountName
} | Select-Object -First $MAX_LENGTH |
Sort-Object TimeCreated |
Format-Table -AutoSize
