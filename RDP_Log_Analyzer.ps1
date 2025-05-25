# 全局配置参数
$USER_FILTER = @() # 要过滤的用户列表，空数组表示不过滤，示例 '@("uname1", "uname2")'
$MAX_LENGTH = 30   # 最大显示条目数
$MAX_DAY = 30      # 显示日期范围

# 设置时间范围
$startTime = (Get-Date).AddDays(-$MAX_DAY).Date

# 定义常见的登录失败原因映射表
$failureReasonMap = @{
    '%%2305' = '指定的用户帐户已过期'
    '%%2309' = '指定帐户的密码已过期'
    '%%2310' = '帐户当前已禁用'
    '%%2311' = '帐户登录时间限制违规'
    '%%2312' = '用户不允许在此计算机上登录'
    '%%2313' = '用户名或密码错误'
}

# 获取最近一个月的 RDP 登录成功事件（事件ID 1149）
$successEvents = Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'
    ID        = 1149
    StartTime = $startTime
} -ErrorAction SilentlyContinue

Write-Host "`n=== 登录日志 ===`n"

# 解析并显示成功事件（带过滤和限制）
$successEvents | ForEach-Object {
    $messageLines = $_.Message -split "`n"
    
    $user = ($messageLines | 
        Where-Object { $_ -match "用户:" } | 
        ForEach-Object { ($_ -split '用户:')[1].Trim() }
    )

    $domain = ($messageLines | 
        Where-Object { $_ -match "域:" } | 
        ForEach-Object { ($_ -split '域:')[1].Trim() }
    )

    $sourceIP = ($messageLines | 
        Where-Object { $_ -match "源网络地址:" } | 
        ForEach-Object { ($_ -split '源网络地址:')[1].Trim() }
    )

    [PSCustomObject]@{
        TimeCreated = $_.TimeCreated
        User        = $user
        Domain      = $domain
        SourceIP    = $sourceIP
    }
} | Where-Object {
    # 用户过滤逻辑
    $USER_FILTER.Count -eq 0 -or $USER_FILTER -contains $_.User
} | Select-Object -First $MAX_LENGTH | Sort-Object TimeCreated |
Format-Table -AutoSize -Property TimeCreated, User, Domain, SourceIP

Write-Host "`n=== 失败日志 ===`n"

# 获取登录失败事件（事件 ID 4625）
$failureEvents = Get-WinEvent -FilterHashtable @{
    LogName   = 'Security'
    ID        = 4625
    StartTime = $startTime
} -ErrorAction SilentlyContinue

# 解析并显示失败事件（带过滤和限制）
$failureEvents | ForEach-Object {
    $xml = [xml]$_.ToXml()
    $data = @{}
    $xml.Event.EventData.Data | ForEach-Object { $data[$_.Name] = $_.'#text' }
    
    [PSCustomObject]@{
        TimeCreated     = $_.TimeCreated
        AccountName     = $data['TargetUserName']
        AccountDomain   = $data['TargetDomainName']
        FailureReason   = if ($failureReasonMap.ContainsKey($data['FailureReason'])) {
            $failureReasonMap[$data['FailureReason']]
        } else {
            $data['FailureReason']
        }
        SourceIPAddress = $data['IpAddress']
        SourcePort      = $data['IpPort']
    }
} | Where-Object {
    # 用户过滤逻辑
    $USER_FILTER.Count -eq 0 -or $USER_FILTER -contains $_.AccountName
} | Sort-Object TimeCreated -Descending | 
Select-Object -First $MAX_LENGTH | 
Format-Table -AutoSize
