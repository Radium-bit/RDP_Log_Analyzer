param (
    [switch]$e,  # 只显示删除/修改行为
    [switch]$r   # 只显示读取行为
)

# === 配置参数 ===
$USER_FILTER = @() # 要过滤的用户列表，空数组表示不过滤，示例 '@("uname1", "uname2")'
$MAX_LENGTH = 30
$MAX_DAY = 30
$startTime = (Get-Date).AddDays(-$MAX_DAY).Date

# === 权限位标识===
$accessMap = @{
    0x1      = '读取数据'
    0x8      = '读取属性'
    0x2      = '写入数据'
    0x4      = '追加数据'
    0x10     = '写入扩展属性'
    0x80     = '写入属性'
    0x10000  = '删除'
    0x40000  = '删除子项'
}

# 将权限按类别分组
$readBits  = @(0x1, 0x8)
$writeBits = @(0x2, 0x4, 0x10, 0x80, 0x10000, 0x40000)

# === 获取事件 ===
$events = Get-WinEvent -FilterHashtable @{
    LogName   = 'Security'
    ID        = 4663
    StartTime = $startTime
} -ErrorAction SilentlyContinue

$readResult = @()
$writeResult = @()

foreach ($event in $events) {
    $xml = [xml]$event.ToXml()
    $data = @{}
    $xml.Event.EventData.Data | ForEach-Object { $data[$_.Name] = $_.'#text' }

    $user = $data['SubjectUserName']
    $object = $data['ObjectName']
    $rawMask = $data['AccessMask']

    # 排除系统账户和无效数据
    if ($user -like '*$' -or !$object -or !$rawMask) {
        continue
    }

    # 用户过滤
    if ($USER_FILTER.Count -gt 0 -and -not ($USER_FILTER -contains $user)) {
        continue
    }

    # 转换为整数
    $mask = [int]("0x$rawMask")

    # 找出命中的权限（多权限组合）
    $matches = $accessMap.Keys | Where-Object { $mask -band $_ } | ForEach-Object { $accessMap[$_] }

    # 构造输出项
    $entry = [PSCustomObject]@{
        时间 = $event.TimeCreated.ToString("yyyy/MM/dd HH:mm:ss")
        用户 = $user
        路径 = $object
        行为 = ($matches -join ', ')
    }

    # 分类加入
    if ($writeBits | Where-Object { $mask -band $_ }) {
        $writeResult += $entry
    }
    elseif ($readBits | Where-Object { $mask -band $_ }) {
        $readResult += $entry
    }
}

# === 输出 ===
if (-not $r) {
    Write-Host "`n=== 删改请求 ===`n" -ForegroundColor Yellow
    $writeResult | Sort-Object 时间 | Select-Object -First $MAX_LENGTH | Format-Table -AutoSize
}
if (-not $e) {
    Write-Host "`n=== 读取请求 ===`n" -ForegroundColor Cyan
    $readResult | Sort-Object 时间 | Select-Object -First $MAX_LENGTH | Format-Table -AutoSize
}
