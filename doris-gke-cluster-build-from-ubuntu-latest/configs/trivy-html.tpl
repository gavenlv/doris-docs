<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Trivy Security Report</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 { color: #333; }
        h2 { color: #666; margin-top: 30px; }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .stat {
            padding: 15px;
            border-radius: 8px;
            text-align: center;
        }
        .stat-critical { background: #fee; color: #c00; }
        .stat-high { background: #ffe; color: #c80; }
        .stat-medium { background: #ffc; color: #880; }
        .stat-low { background: #efe; color: #080; }
        .stat h3 { margin: 0; font-size: 2em; }
        .stat p { margin: 5px 0 0; }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th { background: #f8f8f8; }
        tr:hover { background: #f5f5f5; }
        .severity {
            padding: 4px 8px;
            border-radius: 4px;
            font-weight: bold;
            font-size: 0.9em;
        }
        .CRITICAL { background: #fdd; color: #c00; }
        .HIGH { background: #fed; color: #c80; }
        .MEDIUM { background: #ffd; color: #880; }
        .LOW { background: #dfd; color: #080; }
        .UNKNOWN { background: #eee; color: #888; }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #ddd;
            color: #666;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Trivy Security Scan Report</h1>
        <p>Generated: {{ now }}</p>
        
        <div class="summary">
            <div class="stat stat-critical">
                <h3>{{ .TotalCritical }}</h3>
                <p>Critical</p>
            </div>
            <div class="stat stat-high">
                <h3>{{ .TotalHigh }}</h3>
                <p>High</p>
            </div>
            <div class="stat stat-medium">
                <h3>{{ .TotalMedium }}</h3>
                <p>Medium</p>
            </div>
            <div class="stat stat-low">
                <h3>{{ .TotalLow }}</h3>
                <p>Low</p>
            </div>
        </div>

        {{ range .Results }}
        <h2>{{ .Target }}</h2>
        {{ if .Vulnerabilities }}
        <table>
            <thead>
                <tr>
                    <th>CVE</th>
                    <th>Severity</th>
                    <th>Package</th>
                    <th>Installed</th>
                    <th>Fixed</th>
                    <th>Description</th>
                </tr>
            </thead>
            <tbody>
                {{ range .Vulnerabilities }}
                <tr>
                    <td><a href="https://nvd.nist.gov/vuln/detail/{{ .VulnerabilityID }}" target="_blank">{{ .VulnerabilityID }}</a></td>
                    <td><span class="severity {{ .Severity }}">{{ .Severity }}</span></td>
                    <td>{{ .PkgName }}</td>
                    <td>{{ .InstalledVersion }}</td>
                    <td>{{ .FixedVersion }}</td>
                    <td>{{ .Title }}</td>
                </tr>
                {{ end }}
            </tbody>
        </table>
        {{ else }}
        <p style="color: green; font-weight: bold;">No vulnerabilities found!</p>
        {{ end }}
        {{ end }}

        <div class="footer">
            <p>Scanned with Trivy - <a href="https://aquasecurity.github.io/trivy/">https://aquasecurity.github.io/trivy/</a></p>
        </div>
    </div>
</body>
</html>
