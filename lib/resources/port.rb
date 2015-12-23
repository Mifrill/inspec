# encoding: utf-8
# author: Christoph Hartmann
# author: Dominik Richter

# Usage:
# describe port(80) do
#   it { should be_listening }
#   its('protocol') {should eq 'tcp'}
# end
#
# not supported serverspec syntax
# describe port(80) do
#   it { should be_listening.with('tcp') }
# end
#
# TODO: currently we return local ip only
# TODO: improve handling of same port on multiple interfaces
class Port < Inspec.resource(1)
  name 'port'
  desc "Use the port InSpec audit resource to test basic port properties, such as port, process, if it's listening."
  example "
    describe port(80) do
      it { should be_listening }
      its('protocols') {should eq ['tcp']}
    end
  "

  def initialize(ip = nil, port) # rubocop:disable OptionalArguments
    @ip = ip
    @port = port
    @port_manager = nil
    @cache = nil

    case inspec.os[:family]
    when 'ubuntu', 'debian', 'redhat', 'fedora', 'centos', 'arch', 'wrlinux'
      @port_manager = LinuxPorts.new(inspec)
    when 'darwin', 'aix'
      # AIX: see http://www.ibm.com/developerworks/aix/library/au-lsof.html#resources
      #      and https://www-01.ibm.com/marketing/iwm/iwm/web/reg/pick.do?source=aixbp
      # Darwin: https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man8/lsof.8.html
      # I think all lsof's are the same...
      @port_manager = LsofPorts.new(inspec)
    # when 'redhat' - I think most lsof's are the same and pretty standard on many linuxes
    #   @port_manager = LsofPorts.new(inspec, '/usr/sbin/lsof')
    when 'windows'
      @port_manager = WindowsPorts.new(inspec)
    when 'freebsd'
      @port_manager = FreeBsdPorts.new(inspec)
    else
      return skip_resource 'The `port` resource is not supported on your OS yet.'
    end
  end

  def listening?(_protocol = nil, _local_address = nil)
    info.size > 0
  end

  def protocols
    res = info.map { |x| x[:protocol] }.uniq.compact
    res.size > 0 ? res : nil
  end

  def processes
    res = info.map { |x| x[:process] }.uniq.compact
    res.size > 0 ? res : nil
  end

  def pids
    res = info.map { |x| x[:pid] }.uniq.compact
    res.size > 0 ? res : nil
  end

  def to_s
    "Port  #{@port}"
  end

  private

  def info
    return @cache if !@cache.nil?
    # abort if os detection has not worked
    return @cache = [] if @port_manager.nil?
    # query ports
    ports = @port_manager.info || []
    @cache = ports.select { |p| p[:port] == @port && (!@ip || p[:address] == @ip) }
  end
end

# implements an info method and returns all ip adresses and protocols for
# each port
# [{
#   port: 22,
#   address: '0.0.0.0'
#   protocol: 'tcp'
# },
# {
#   port: 22,
#   address: '::'
#   protocol: 'tcp6'
# }]
class PortsInfo
  attr_reader :inspec
  def initialize(inspec)
    @inspec = inspec
  end
end

# TODO: Add UDP infromation Get-NetUDPEndpoint
# TODO: currently Windows only supports tcp ports
# TODO: Get-NetTCPConnection does not return PIDs
# TODO: double-check output with 'netstat -ano'
# @see https://connect.microsoft.com/PowerShell/feedback/details/1349420/get-nettcpconnection-does-not-show-processid
class WindowsPorts < PortsInfo
  def info
    # get all port information
    cmd = inspec.command('Get-NetTCPConnection | Select-Object -Property State, Caption, Description, LocalAddress, LocalPort, RemoteAddress, RemotePort, DisplayName, Status | ConvertTo-Json')

    begin
      ports = JSON.parse(cmd.stdout)
    rescue JSON::ParserError => _e
      return nil
    end

    return nil if ports.nil?

    ports.map { |x|
      {
        port: x['LocalPort'],
        address: x['LocalAddress'],
        protocol: 'tcp',
        process: nil,
        pid: nil,
      }
    }
  end
end

# extracts udp and tcp ports from the lsof command
class LsofPorts < PortsInfo
  attr_reader :lsof
<<<<<<< HEAD

  def initialize(inspec, lsofpath = nil)
    @lsof = lsofpath || 'lsof'
    super(inspec)
  end

  def info
    ports = []

    # -F p=pid, c=command, P=protocol name, t=type, n=internet addresses
    # see 'OUTPUT FOR OTHER PROGRAMS' in LSOF(8)
    lsof_cmd = inspec.command("#{@lsof} -nP -i -FpctPn")
    return nil if lsof_cmd.exit_status.to_i != 0

    # map to desired return struct
    lsof_parser(lsof_cmd).each do |process, port_ids|
      pid, cmd = process.split(':')
      port_ids.each do |port_str|
        # should not break on ipv6 addresses
        ipv, proto, port, host = port_str.split(':', 4)
        ports.push({ port:  port.to_i,
                     address:  host,
                     protocol: ipv == 'ipv6' ? proto + '6' : proto,
                     process:  cmd,
                     pid:      pid.to_i })
=======

  def initialize(inspec, lsofpath = nil)
    @lsof = lsofpath || 'lsof'
    super(inspec)
  end

  def info
    ports = []
    # -F p=pid, c=command, P=protocol name, t=type, n=internet addresses
    # see 'OUTPUT FOR OTHER PROGRAMS' in LSOF(8)
    lsof_cmd = inspec.command("#{@lsof} -nP -iTCP -iUDP -FpctPn")
    return nil if lsof_cmd.exit_status.to_i != 0

    # build this with formatted output (-F) from lsof
    procs = {}
    # procs = {
    #   '123:sshd' => [
    #      'ipv4:tcp:22:127.0.0.1',
    #      'ipv6:tcp:22:::1',
    #      'ipv4:tcp:*',
    #      'ipv6:tcp:*',
    #   ],
    #   '456:ntpd' => [
    #      'ipv4:udp:123:*',
    #      'ipv6:udp:123:*',
    #   ]
    # }
    proc_id = port_id = nil
    pid = cmd = ipv = proto = port = host = nil
    lsof_cmd.stdout.each_line do |line|
      line.chomp!
      key = line.slice!(0)
      case key
      when 'p'
        proc_id = line
        port_id = nil
      when 'c'
        proc_id += ':' + line
      when 't'
        port_id = line.downcase
      when 'P'
        port_id += ':' + line.downcase
      when 'n'
        src, dst = line.split('->')

        # skip active comm streams
        next if dst

        host, port = /^(\S+):(\d+|\*)$/.match(src)[1,2]

        # skip channels from port 0 - what does this mean?
        next if port == '*'

        # create new array stub if !exist?
        procs[proc_id] = [] unless procs.key?(proc_id)

        # change address '*' to zero
        host = (port_id =~ /^ipv6:/) ? '[::]' : '0.0.0.0' if host == '*'
        # entrust URI to scrub the host and port
        begin
          uri = URI("addr://#{host}:#{port}")
          uri.host && uri.port
        rescue Exception => e
          warn "could not parse uri addr://#{host}:#{port} - #{e}"
          next
        end

        # e.g. 'ipv4:tcp:22:127.0.0.1' or
        #                             strip ipv6 squares for inspec
        port_id += ':' + port + ':' + host.gsub(/^\[|\]$/, '')

        # lsof will give us another port or it's done
        procs[proc_id] << port_id
      end
    end

    # map to desired return struct
    procs.each do |proc_id, port_ids|
      pid, cmd = proc_id.split(':')
      port_ids.each do |port_id|
        # should not break on ipv6 addresses
        ipv, proto, port, host = port_id.split(':', 4)
        ports.push({
          port:     port.to_i,
          address:  host,
          protocol: ipv == 'ipv6' ? proto + '6' : proto,
          process:  cmd,
          pid:      pid.to_i,
        })
>>>>>>> 476d5d8... use formmated lsof output to ensure accuracy and consistency across platforms
      end
    end

    ports
  end

  # rubocop:disable Metrics/CyclomaticComplexity
  # rubocop:disable Metrics/AbcSize
  def lsof_parser(lsof_cmd)
    procs = {}
    # build this with formatted output (-F) from lsof
    # procs = {
    #   '123:sshd' => [
    #      'ipv4:tcp:22:127.0.0.1',
    #      'ipv6:tcp:22:::1',
    #      'ipv4:tcp:*',
    #      'ipv6:tcp:*',
    #   ],
    #   '456:ntpd' => [
    #      'ipv4:udp:123:*',
    #      'ipv6:udp:123:*',
    #   ]
    # }
    proc_id = port_id = nil
    lsof_cmd.stdout.each_line do |line|
      line.chomp!
      key = line.slice!(0)
      case key
      when 'p'
        proc_id = line
        port_id = nil
      when 'c'
        proc_id += ':' + line
      when 't'
        port_id = line.downcase
      when 'P'
        port_id += ':' + line.downcase
      when 'n'
        src, dst = line.split('->')

        # skip active comm streams
        next if dst

        host, port = /^(\S+):(\d+|\*)$/.match(src)[1, 2]

        # skip channels from port 0 - what does this mean?
        next if port == '*'

        # create new array stub if !exist?
        procs[proc_id] = [] unless procs.key?(proc_id)

        # change address '*' to zero
        host = (port_id =~ /^ipv6:/) ? '[::]' : '0.0.0.0' if host == '*'
        # entrust URI to scrub the host and port
        begin
          uri = URI("addr://#{host}:#{port}")
          uri.host && uri.port
        rescue => e
          warn "could not parse URI 'addr://#{host}:#{port}' - #{e}"
          next
        end

        # e.g. 'ipv4:tcp:22:127.0.0.1'
        #                             strip ipv6 squares for inspec
        port_id += ':' + port + ':' + host.gsub(/^\[|\]$/, '')

        # lsof will give us another port unless it's done
        procs[proc_id] << port_id
      end
    end

    procs
  end
end

# extract port information from netstat
class LinuxPorts < PortsInfo
  def info
    cmd = inspec.command('netstat -tulpen')
    return nil if cmd.exit_status.to_i != 0

    ports = []
    # parse all lines
    cmd.stdout.each_line do |line|
      port_info = parse_netstat_line(line)

      # only push protocols we are interested in
      next unless %w{tcp tcp6 udp udp6}.include?(port_info[:protocol])
      ports.push(port_info)
    end
    ports
  end

  def parse_net_address(net_addr, protocol)
    if protocol.eql?('tcp6') || protocol.eql?('udp6')
      # prep for URI parsing, parse ip6 port
      ip6 = /^(\S+):(\d+)$/.match(net_addr)
      ip6addr = ip6[1]
      ip6addr = '::' if ip6addr =~ /^:::$/
      # build uri
      ip_addr = URI("addr://[#{ip6addr}]:#{ip6[2]}")
      # replace []
      host = ip_addr.host[1..ip_addr.host.size-2]
    else
      ip_addr = URI('addr://'+net_addr)
      host = ip_addr.host
    end

    port = ip_addr.port

    [host, port]
  rescue URI::InvalidURIError => e
    warn "Could not parse #{net_addr}, #{e}"
    nil
  end

  def parse_netstat_line(line)
    # parse each line
    # 1 - Proto, 2 - Recv-Q, 3 - Send-Q, 4 - Local Address, 5 - Foreign Address, 6 - State, 7 - Inode, 8 - PID/Program name
    parsed = /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)?\s+(\S+)\s+(\S+)\s+(\S+)/.match(line)

    return {} if parsed.nil? || line.match(/^proto/i)

    # parse ip4 and ip6 addresses
    protocol = parsed[1].downcase

    # detect protocol if not provided
    protocol += '6' if parsed[4].count(':') > 1 && %w{tcp udp}.include?(protocol)

    # extract host and port information
    host, port = parse_net_address(parsed[4], protocol)

    # extract PID
    process = parsed[9].split('/')
    pid = process[0]
    pid = pid.to_i if pid =~ /^\d+$/
    process = process[1]

    # map data
    {
      port: port,
      address: host,
      protocol: protocol,
      process: process,
      pid: pid,
    }
  end
end

# extracts information from sockstat
class FreeBsdPorts < PortsInfo
  def info
    cmd = inspec.command('sockstat -46l')
    return nil if cmd.exit_status.to_i != 0

    ports = []
    # split on each newline
    cmd.stdout.each_line do |line|
      port_info = parse_sockstat_line(line)

      # push data, if not headerfile
      next unless %w{tcp tcp6 udp udp6}.include?(port_info[:protocol])
      ports.push(port_info)
    end
    ports
  end

  def parse_net_address(net_addr, protocol)
    case protocol
    when 'tcp4', 'udp4'
      # replace * with 0.0.0.0
      net_addr = net_addr.gsub(/^\*:/, '0.0.0.0:') if net_addr =~ /^*:(\d+)$/
      ip_addr = URI('addr://'+net_addr)
      host = ip_addr.host
      port = ip_addr.port
    when 'tcp6', 'udp6'
      return [] if net_addr == '*:*' # abort for now
      # replace * with 0:0:0:0:0:0:0:0
      net_addr = net_addr.gsub(/^\*:/, '0:0:0:0:0:0:0:0:') if net_addr =~ /^*:(\d+)$/
      # extract port
      ip6 = /^(\S+):(\d+)$/.match(net_addr)
      ip6addr = ip6[1]
      ip_addr = URI("addr://[#{ip6addr}]:#{ip6[2]}")
      # replace []
      host = ip_addr.host[1..ip_addr.host.size-2]
      port = ip_addr.port
    end
    [host, port]
  rescue URI::InvalidURIError => e
    warn "Could not parse #{net_addr}, #{e}"
    nil
  end

  def parse_sockstat_line(line)
    # 1 - USER, 2 - COMMAND, 3 - PID, 4 - FD 5 - PROTO, 6 - LOCAL ADDRESS, 7 - FOREIGN ADDRESS
    parsed = /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$/.match(line)
    return {} if parsed.nil?

    # extract ip information
    protocol = parsed[5].downcase
    host, port = parse_net_address(parsed[6], protocol)
    return {} if host.nil? or port.nil?

    # extract process
    process = parsed[2]

    # extract PID
    pid = parsed[3]
    pid = pid.to_i if pid =~ /^\d+$/

    # map tcp4 and udp4
    protocol = 'tcp' if protocol.eql?('tcp4')
    protocol = 'udp' if protocol.eql?('udp4')

    # map data
    {
      port: port,
      address: host,
      protocol: protocol,
      process: process,
      pid: pid,
    }
  end
end
