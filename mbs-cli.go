package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"html"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"os/user"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"gopkg.in/yaml.v2"
)

// We go Scheme / host / MBS_API

// MBS_Scheme How to connet to MBS
const MBS_Scheme = "http://"

// MBS_API Instance of MBS to connect to
const MBS_API = "/module-build-service/1/module-builds/"

const MBSDefaultHost = "mbs.fedoraproject.org"

const (
	cacheListTime = time.Minute * 8
	cacheIDTime   = time.Hour * 24 * 7
)

var refresh_flag bool
var verbose_flag bool
var arch_flag string
var host_flag string

func init() {
	flag.BoolVar(&refresh_flag, "refresh", false, "Force refresh main list")
	flag.BoolVar(&verbose_flag, "verbose", false, "Print rpms")
	flag.StringVar(&arch_flag, "arch", "<arch>", "Arch for rpm URLs (hack)")
	flag.StringVar(&host_flag, "host", MBSDefaultHost, "Host running MBS")
}

func MBSURL() string {
	return MBS_Scheme + host_flag + MBS_API
}

func worker_all(bchan chan *MBSAPI, vchan chan *Build, cvchan chan int, wg *sync.WaitGroup) {
	done := false

	var pwg sync.WaitGroup
	for b := range bchan {
		if b == nil {
			continue
		}
		if !done && b.Meta.Pages > 1 {
			for num := 2; num <= b.Meta.Pages; num++ {
				pwg.Add(1)
				url := fmt.Sprintf("%s?per_page=%d&page=%d",
					MBSURL(), b.Meta.Per_page, num)
				go func() { bchan <- builds(url); pwg.Done() }()
			}
			go func() {
				pwg.Wait()
				close(bchan)
			}()
			done = true
		}

		for i := range b.Items {
			item := b.Items[i]
			// fmt.Printf("JDBG: %+v\n", item)
			if item.State != 5 {
				continue
			}
			wg.Add(1)
			go func() {
				if cvchan != nil {
					cvchan <- item.ID
				}
				vchan <- build(item.ID)
				wg.Done()
			}()
		}
	}
	wg.Done()

}

func worker_iter(bchan chan *MBSAPI, vchan chan *Build, cvchan chan int, wg *sync.WaitGroup) {
	for b := range bchan {
		if b == nil {
			continue
		}

		for i := range b.Items {
			item := b.Items[i]
			// fmt.Printf("JDBG: %+v\n", item)
			if item.State != 5 {
				continue
			}
			wg.Add(1)
			go func() {
				if cvchan != nil {
					cvchan <- item.ID
				}
				vchan <- build(item.ID)
				wg.Done()
			}()
		}

		if b.Meta.Next == "" {
			close(bchan)
		} else {
			wg.Add(1)
			url := b.Meta.Next
			go func() { bchan <- builds(url); wg.Done() }()
		}
	}

	wg.Done()
}

func sort_builds(schan chan *Build, vchan chan *Build) {
	var bds []*Build
	for bd := range vchan {
		if bd == nil {
			continue
		}
		bds = append(bds, bd)
	}
	// sort.Slice(bds, func(i, j int) bool { return bds[i].ID < bds[j].ID })
	sort.Slice(bds, func(i, j int) bool { return bds[i].Time_completed.Before(bds[j].Time_completed) })
	for i := range bds {
		schan <- bds[i]
	}
	close(schan)
}

func main() {
	var wg sync.WaitGroup

	flag.Parse()

	args := flag.Args()
	if len(args) < 1 {
		args = []string{"list"}
	}

	bchan := make(chan *MBSAPI, 64)
	vchan := make(chan *Build, 64)
	var cvchan chan int
	schan := make(chan *Build)

	var cached_list bool
	var list_data []byte
	path := cachePath()
	if path == "" {
		// Nothing
	} else if !refresh_flag {
		fpath := path + "/list"
		file, err := os.Open(fpath)
		if err == nil {
			defer file.Close()
			fi, err := file.Stat()
			if err == nil && time.Since(fi.ModTime()) <= cacheListTime {
				list_data, err = ioutil.ReadAll(file)
				if err == nil {
					cached_list = true
				}
			}
		}
	}

	if !cached_list { // Try to create a cache for next time
		cached_list = false
		os.MkdirAll(path, os.ModePerm)
		fpath := path + "/list"
		file, err := os.Create(fpath)
		if err == nil {
			cvchan = make(chan int)
			go func() {
				for ID := range cvchan {
					fmt.Fprintf(file, "%d\n", ID)
				}
				file.Close()
			}()
		}
	}

	wg.Add(1)
	if !cached_list {
		go func() { bchan <- builds(fmt.Sprintf("%s?per_page=100", MBSURL())) }()
		// go func() { bchan <- builds(MBSURL()) }()
		go worker_all(bchan, vchan, cvchan, &wg)
	} else {
		go func() {
			close(bchan)
			scanner := bufio.NewScanner(bytes.NewReader(list_data))

			for scanner.Scan() {
				line := scanner.Text()
				num64, err := strconv.ParseInt(line, 10, 64)
				if err != nil {
					continue
				}
				num := int(num64)

				wg.Add(1)
				go func() { vchan <- build(num); wg.Done() }()
			}
			wg.Done()
		}()
	}
	go sort_builds(schan, vchan)
	go func() {
		wg.Wait()
		if cvchan != nil {
			close(cvchan)
		}

		close(vchan)
	}()

	if false {
	} else if args[0] == "dlmod" {
		cmd_dlmod(schan, args)
	} else if args[0] == "dlrpms" {
		cmd_dlrpms(schan, args)
	} else if args[0] == "profiles" {
		cmd_profiles(schan, args)
	} else if args[0] == "html" {
		cmd_html(schan, args)
	} else if args[0] == "info" {
		cmd_info(schan, args)
	} else if args[0] == "list" {
		cmd_list(schan, args)
	} else if args[0] == "modmd" {
		cmd_modmd(schan, args)
	} else if args[0] == "uncache" {
		cmd_uncache(schan, &args)
	} else {
		fmt.Println("Error: Bad sub-command:", args[0])
	}
}

func match(pattern, name, stream, version string) (matched bool) {
	if m, _ := filepath.Match(pattern, name); m {
		return true
	}
	// Old style
	ns := fmt.Sprintf("%s-@%s", name, stream)
	if m, _ := filepath.Match(pattern, ns); m {
		return true
	}
	nsv := fmt.Sprintf("%s-@%s-%s", name, stream, version)
	if m, _ := filepath.Match(pattern, nsv); m {
		return true
	}
	// New style
	if pattern[0] == '@' {
		pattern = pattern[1:]
	}
	if slash := strings.LastIndex(pattern, "/"); slash != -1 {
		pattern = pattern[:slash]
	}
	ns = fmt.Sprintf("%s:%s", name, stream)
	if m, _ := filepath.Match(pattern, ns); m {
		return true
	}
	nsv = fmt.Sprintf("%s:%s:%s", name, stream, version)
	if m, _ := filepath.Match(pattern, nsv); m {
		return true
	}
	return false
}

func filter(vchan chan *Build, args []string) chan *Build {
	ochan := make(chan *Build)
	go func() {
		for bres := range vchan {
			if bres == nil {
				continue
			}

			if len(args) > 1 && !match(args[1], bres.Name, bres.Stream, bres.Version) {
				continue
			}
			ochan <- bres
		}
		close(ochan)
	}()
	return ochan
}

func build_prnthdr(bres *Build) {
	fmt.Printf("Build %5d | %s @%s-%s | %s\n", bres.ID,
		bres.Name, bres.Stream, bres.Version, bres.Owner)
}

func iter_rpms(rpms map[string]Rpm) []string {
	var ret []string
	for name := range rpms {
		ret = append(ret, name)
	}

	sort.Slice(ret, func(i, j int) bool { return ret[i] < ret[j] })
	return ret
}

func cmd_list(vchan chan *Build, args []string) {

	for bres := range filter(vchan, args) {
		build_prnthdr(bres)
		if !verbose_flag {
			continue
		}
		for _, name := range iter_rpms(bres.Tasks.Rpms) {
			rpm := bres.Tasks.Rpms[name]
			if rpm.State == 1 {
				fmt.Printf("  %s %s\n", name, rpm.NVR)
			} else {
				fmt.Printf("  %s %s ** %d %s\n", name, rpm.NVR, rpm.State, rpm.State_reason)
			}
		}
	}

	time.Now()
	// fmt.Printf("%+v", tres)
}

func uitime(tm time.Time) string {
	return tm.Format("2006-01-02 15:04:05 MST")
}

func uiscm(url string) string {
	re := regexp.MustCompile("git://(pkgs[.]fedoraproject[.]org/modules/[^/]+)[?]#([0-9abcdef]+)$")
	return re.ReplaceAllString(url, "http://$1/c/$2")
}

func clone_diff_scm(ourl, nurl string) string {
	re := regexp.MustCompile("git://(pkgs[.]fedoraproject[.]org/modules/)([^/]+)[?]#([0-9abcdef]+)$")
	ret := re.ReplaceAllString(ourl, `	git clone http://$1$2;
	cd $2;
	git reset -q --hard $3;
	git log -p --stat $3..`)
	ret += re.ReplaceAllString(nurl, `$3;
	cd ..;
	rm -rf $2
`)
	return ret
}

func cmd_info(vchan chan *Build, args []string) {
	for bres := range filter(vchan, args) {
		build_prnthdr(bres)
		fmt.Printf(" Submitted: %s\n", uitime(bres.Time_submitted))
		fmt.Printf(" Completed: %s\n", uitime(bres.Time_completed))
		fmt.Printf(" Modified:  %s\n", uitime(bres.Time_modified))
		fmt.Printf(" SCM:  %s\n", uiscm(bres.SCMURL))
		for _, name := range iter_rpms(bres.Tasks.Rpms) {
			rpm := bres.Tasks.Rpms[name]
			if rpm.State == 1 {
				fmt.Printf("  %s %s\n", name, rpm.NVR)
			} else {
				fmt.Printf("  %s %s ** %d %s\n", name, rpm.NVR, rpm.State, rpm.State_reason)
			}
		}
	}
}

func cmd_dlrpms(vchan chan *Build, args []string) {
	for bres := range filter(vchan, args) {
		build_prnthdr(bres)
		for _, name := range iter_rpms(bres.Tasks.Rpms) {
			rpm := bres.Tasks.Rpms[name]
			if rpm.State == 1 {
				// https://koji.fedoraproject.org/koji/taskinfo?taskID=19059540
				// https://kojipkgs.fedoraproject.org//packages/ed/1.14.1/2.module_3fd5254d/x86_64/ed-1.14.1-2.module_3fd5254d.x86_64.rpm
				reli := strings.LastIndex(rpm.NVR, "-")
				if reli == -1 {
					continue
				}
				rel := string(rpm.NVR[reli+1:])
				ver := string(rpm.NVR[len(name)+1 : reli])
				dirarch := arch_flag
				if arch_flag == "<arch>" {
					dirarch = "\n  <arch>"
				}
				fmt.Printf("%s/%s/%s/%s/%s/%s.%s.rpm\n",
					"https://kojipkgs.fedoraproject.org/packages",
					name, ver, rel, dirarch, rpm.NVR, arch_flag)
			}
		}
	}
}

func cmd_dlmod(vchan chan *Build, args []string) {
	for bres := range filter(vchan, args) {
		build_prnthdr(bres)

		modfname := fmt.Sprintf("%s-@%s-%s.modmd",
			bres.Name, bres.Stream, bres.Version)
		out, err := os.Create(modfname)
		if err != nil {
			panic(err)
		}
		defer out.Close()

		modmd_suffix := `
document: modulemd
version: 1
`
		if !strings.HasSuffix(bres.ModuleMD, modmd_suffix) {
			panic(fmt.Errorf("weird modmd"))
		}

		fmt.Fprintf(out, "%s",
			strings.TrimSuffix(bres.ModuleMD, modmd_suffix))
		fmt.Fprintf(out, "\n")
		fmt.Fprintf(out, "  artifacts:\n")
		fmt.Fprintf(out, "    rpms:\n")

		var wg sync.WaitGroup
		for _, name := range iter_rpms(bres.Tasks.Rpms) {
			rpm := bres.Tasks.Rpms[name]
			if rpm.State == 1 {
				// https://koji.fedoraproject.org/koji/taskinfo?taskID=19059540
				// https://kojipkgs.fedoraproject.org//packages/ed/1.14.1/2.module_3fd5254d/x86_64/ed-1.14.1-2.module_3fd5254d.x86_64.rpm
				reli := strings.LastIndex(rpm.NVR, "-")
				if reli == -1 {
					continue
				}
				rel := string(rpm.NVR[reli+1:])
				ver := string(rpm.NVR[len(name)+1 : reli])

				// FIXME: Try x86_64 and then noarch
				//				rpmname := fmt.Sprintf("%s.%s", rpm.NVR, "x86_64")
				//				url := fmt.Sprintf("%s/%s/%s/%s/%s/%s.rpm",
				//					"https://kojipkgs.fedoraproject.org/packages",
				//					name, ver, rel, "x86_64", rpmname)

				for _, arch := range []string{"noarch", "x86_64"} {
					url := fmt.Sprintf("%s/%s/%s/%s/%s",
						"https://kojipkgs.fedoraproject.org/packages",
						name, ver, rel, arch)

					resp, err := http.Get(url)
					if err == nil && resp.StatusCode == 404 {
						resp.Body.Close()
						err = fmt.Errorf("Not found: %s", url)
						continue
					}
					bbody, err := ioutil.ReadAll(resp.Body)
					if err != nil {
						panic(err)
					}
					resp.Body.Close()

					body := string(bbody)

					re := regexp.MustCompile("<a href=\"([^\"]*[.]rpm)\">")
					for _, rpmlist := range re.FindAllStringSubmatch(body, -1) {
						rpmurl := rpmlist[1]
						rpmfname := path.Base(rpmurl)
						rpmname := strings.TrimSuffix(rpmfname, ".rpm")

						resp, err = http.Get(url + "/" + rpmurl)
						if err == nil && resp.StatusCode == 404 {
							resp.Body.Close()
							err = fmt.Errorf("Not found: %s %s", url, rpmname)
							panic(err)
						}

						fmt.Println(rpmname)
						fmt.Fprintf(out, "      - %s\n", rpmname)
						wg.Add(1)
						go func() {
							defer resp.Body.Close()
							defer wg.Done()

							rpmout, err := os.Create(rpmfname)
							if err != nil {
								panic(err)
							}
							defer rpmout.Close()

							_, err = io.Copy(rpmout, resp.Body)
							if err != nil {
								panic(err)
							}
						}()
					}
				}
			}
		}
		wg.Wait()
		fmt.Fprintf(out, "%s", strings.TrimPrefix(modmd_suffix, "\n"))
		break
	}
}

type ModMD struct {
	Data struct {
		Profiles map[string]struct{ Rpms []string }
	}
	Document string
	Version  int
}

func cmd_profiles(vchan chan *Build, args []string) {
	for bres := range filter(vchan, args) {
		build_prnthdr(bres)
		modmd := ModMD{}
		yaml.Unmarshal([]byte(bres.ModuleMD), &modmd)
		var profiles []string
		for profile, _ := range modmd.Data.Profiles {
			profiles = append(profiles, profile)
		}
		sort.Strings(profiles)
		fmt.Printf(" Profiles: %s\n", strings.Join(profiles, ", "))
	}
}

func cmd_modmd(vchan chan *Build, args []string) {
	for bres := range filter(vchan, args) {
		fmt.Println(strings.Repeat("=", 79))
		fmt.Printf("%s-@%s-%s.modmd\n", bres.Name, bres.Stream, bres.Version)
		fmt.Println(strings.Repeat("-", 79))
		fmt.Println(bres.ModuleMD)
		fmt.Println(strings.Repeat("-", 79))
		fmt.Printf("  built:\n")
		fmt.Printf("    rpms:\n")

		for _, name := range iter_rpms(bres.Tasks.Rpms) {
			rpm := bres.Tasks.Rpms[name]
			if rpm.State == 1 {
				reli := strings.LastIndex(rpm.NVR, "-")
				if reli == -1 {
					continue
				}
				rel := string(rpm.NVR[reli+1:])
				ver := string(rpm.NVR[len(name)+1 : reli])
				fmt.Printf("      - %s-%d:%s-%s.%s\n",
					name, 0, ver, rel, arch_flag)
			}
		}
	}
}

func rm_files(path string) {
	finfos, err := ioutil.ReadDir(path)
	if err != nil {
		return
	}

	var wg sync.WaitGroup
	for _, finfo := range finfos {
		if finfo.IsDir() {
			continue
		}
		path := path + "/" + finfo.Name()
		wg.Add(1)
		go func() { os.Remove(path); wg.Done() }()
	}
	wg.Wait()
}

func cachePath() string {
	usr, err := user.Current()
	if err != nil {
		return ""
	}
	return buildCachePath(usr)
}

func buildCachePath(usr *user.User) string {
	path := fmt.Sprintf("%s/.cache/mbs-cli/%s", usr.HomeDir, host_flag)
	return path
}

func cmd_uncache(vchan chan *Build, args *[]string) {
	path := cachePath()
	if path == "" {
		return
	}
	rm_files(path)
	rm_files(path + "/ID")
	rm_files(path + "/git")
}

func prnt_rpm_html(out io.Writer, rpm Rpm) {
	if rpm.State == 1 {
		fmt.Fprintf(out, "<li>  %s\n", rpm.NVR)
	} else {
		fmt.Fprintf(out, "<li>  %s ** %d %s\n", rpm.NVR, rpm.State, rpm.State_reason)
	}
}

func build_diff(pbres, bres *Build) string {
	usr, err := user.Current()
	var body []byte
	var path string

	if err == nil && usr.HomeDir != "" {
		path = fmt.Sprintf("%s/git/%d...%d.diff", buildCachePath(usr),
			pbres.ID, bres.ID)
		file, err := os.Open(path) // Should timeout?
		if err == nil {
			defer file.Close()
			body, err = ioutil.ReadAll(file)
			if err == nil {
				return string(body)
			}
		}
	}

	// Gotta get the data...
	dcmds := clone_diff_scm(pbres.SCMURL, bres.SCMURL)
	din := strings.NewReader(dcmds)

	cmd := exec.Command("sh")
	cmd.Stdin = din
	var out bytes.Buffer
	cmd.Stdout = &out

	if cmd.Run() != nil {
		return ""
	}

	go func() {
		os.MkdirAll(filepath.Dir(path), os.ModePerm)
		file, err := os.Create(path) // Should timeout?

		if err == nil {
			r := strings.NewReader(out.String())
			if _, err := io.Copy(file, r); err != nil {
				// FIXME: rename
			}
		}
	}()
	return out.String()
}

func cmd_html(vchan chan *Build, args []string) {

	if len(args) < 3 {
		fmt.Println("Args: http://<webprefix> <outdir>")
		return
	}

	webprefix := args[1]
	outdir := args[2]

	// Summary is only the last bakers two weeks...
	tmfilt := time.Now().AddDate(0, 0, -15)

	os.MkdirAll(outdir+"/builds/", os.ModePerm)

	sum, err := os.Create(outdir + "/index.html")
	if err != nil {
		panic(err)
	}

	full, err := os.Create(outdir + "/builds/index.html")
	if err != nil {
		panic(err)
	}

	var bds []*Build
	//	for bd := range filter(vchan, args) {
	for bd := range vchan {
		if bd == nil {
			continue
		}
		bds = append(bds, bd)
	}

	ownr2bd := make(map[string][]*Build)
	name2bd := make(map[string][]*Build)
	fownr2bd := make(map[string][]*Build)
	fname2bd := make(map[string][]*Build)

	fbds := 0
	for _, bd := range bds {
		name := bd.Name + "/" + bd.Stream
		name2bd[name] = append(name2bd[name], bd)
		ownr2bd[bd.Owner] = append(ownr2bd[bd.Owner], bd)

		if bd.Time_completed.Before(tmfilt) {
			continue
		}
		fbds++
		fname2bd[name] = append(fname2bd[name], bd)
		fownr2bd[bd.Owner] = append(fownr2bd[bd.Owner], bd)
	}

	fmt.Fprintf(sum, `<html>
	<head>
	<title>Modularity overview</title>
	</head>
	<body>
	<h1>Modularity overview report</h1>

	Report generated on %s <hr>
	<h2> Stats. for the past 15 days</h2>
	<ul>
	<li><h3>Builds: %d </h3></li>
	<li><h3>Unique Builds: %d </h3></li>
	<li><h3>Unique Users: %d </h3></li>
	</lu>

	<h2 id="builds"><a href="%s/builds">builds</a></h2>
	<table style="width: 80%%">
	<tr><td style="font-weight: bold">Module</td> 
	    <td style="font-weight: bold">Stream</td>
		<td style="font-weight: bold">Version</td>
		<td style="font-weight: bold">Time</td>
		<td style="font-weight: bold">User</td></tr>
	`,
		uitime(time.Now()), fbds, len(fname2bd), len(fownr2bd), webprefix)

	fmt.Fprintf(full, `<html>
	<head>
	<title>Modularity builds</title>
	</head>
	<body>
	<h1>Modularity builds report</h1>

	Report generated on %s
	<h2> Stats. for all time</h2>
	<ul>
	<li><h3>Builds: %d </h3></li>
	<li><h3>Unique Builds: %d </h3></li>
	<li><h3>Unique Users: %d </h3></li>
	</lu>

	<h2 id="builds"><a href="%s/builds">builds</a></h2>
	<table style="width: 80%%">
	<tr><td style="font-weight: bold">Module</td> 
	    <td style="font-weight: bold">Stream</td>
		<td style="font-weight: bold">Version</td>
		<td style="font-weight: bold">Time</td>
		<td style="font-weight: bold">User</td></tr>
	`,
		uitime(time.Now()), len(bds), len(fname2bd), len(fownr2bd), webprefix)

	pbd2bd := make(map[string]*Build)

	for _, bres := range bds {
		name := bres.Name + "/" + bres.Stream
		pbres := pbd2bd[name]
		pbd2bd[name] = bres

		last_bres := name2bd[name][len(name2bd[name])-1]
		if bres.Time_completed.After(tmfilt) && bres == last_bres {
			if pbres != nil {
				fmt.Fprintf(sum, `	<tr><td><a href="%s/builds/%d...%d.html">%s</a></td><td>%s</td><td>%s</a></td>
		 						<td>%s</td> <td>%s</td></tr>`,
					webprefix, pbres.ID, bres.ID,
					bres.Name, bres.Stream, bres.Version,
					uitime(bres.Time_completed),
					bres.Owner)

			} else {
				fmt.Fprintf(sum, `	<tr><td><a href="%s/builds/%d.html">%s</a></td><td>%s</td><td>%s</a></td>
		 						<td>%s</td> <td>%s</td></tr>`,
					webprefix, bres.ID,
					bres.Name, bres.Stream, bres.Version,
					uitime(bres.Time_completed),
					bres.Owner)
			}
		}
		bout, err := os.Create(outdir + fmt.Sprintf("/builds/%d.html", bres.ID))
		if err != nil {
			panic(err)
		}
		var pout *os.File
		if pbres != nil {
			pout, err = os.Create(outdir + fmt.Sprintf("/builds/%d...%d.html",
				pbres.ID, bres.ID))
			if err != nil {
				panic(err)
			}
		}

		if pbres != nil {
			fmt.Fprintf(full, `	<tr><td><a href="%s/builds/%d...%d.html">%s</a></td><td>%s</td><td>%s</a></td>
		 						<td>%s</td> <td>%s</td></tr>`,
				webprefix, pbres.ID, bres.ID,
				bres.Name, bres.Stream, bres.Version,
				uitime(bres.Time_completed),
				bres.Owner)

		} else {
			fmt.Fprintf(full, `	<tr><td><a href="%s/builds/%d.html">%s</a></td><td>%s</td><td>%s</a></td>
		 						<td>%s</td> <td>%s</td></tr>`,
				webprefix, bres.ID,
				bres.Name, bres.Stream, bres.Version,
				uitime(bres.Time_completed),
				bres.Owner)
		}

		fmt.Fprintf(bout, `<html>
	<head>
	<title>Modularity build %d - %s:%s:%s</title>
	</head>
	<body>
	<h1>Modularity build %d - %s:%s:%s</h1>

	Build data generated %s
	`,
			bres.ID, bres.Name, bres.Stream, bres.Version,
			bres.ID, bres.Name, bres.Stream, bres.Version,
			uitime(time.Now()))

		if pbres != nil {
			fmt.Fprintf(pout, `<html>
	<head>
	<title>Modularity build DIFF %d - %s:%s:%s</title>
	</head>
	<body>
	<h1>Modularity build %s</h1> 
	Module changed from <a href="%s/builds/%d.html">%d - %s:%s</a> =&gt; 
						<a href="%s/builds/%d.html">%d - %s:%s</a> <hr>

	Build data generated %s
	`,
				bres.ID, pbres.Name, bres.Stream, bres.Version,
				pbres.Name,
				webprefix, pbres.ID,
				pbres.ID, pbres.Stream, pbres.Version,
				webprefix, bres.ID,
				bres.ID, bres.Stream, bres.Version,
				uitime(time.Now()))
		}

		fmt.Fprintf(bout, "<h2>Owner</h2> %s\n", bres.Owner)
		if pbres != nil && pbres.Owner != bres.Owner {
			fmt.Fprintf(pout, "<h2>Owner</h2> %s (prev: %s)\n",
				bres.Owner, pbres.Owner)
		} else {
			fmt.Fprintf(pout, "<h2>Owner</h2> %s\n", bres.Owner)
		}

		fmt.Fprintf(bout, "<h3>Submitted</h3> %s\n", uitime(bres.Time_submitted))
		fmt.Fprintf(bout, "(Completed in %s)\n",
			bres.Time_completed.Sub(bres.Time_submitted))
		// fmt.Fprintf(bout, "<h3>Modified</h2> %s\n", uitime(bres.Time_modified))

		fmt.Fprintf(pout, "<h3>Submitted</h3> %s\n", uitime(bres.Time_submitted))
		fmt.Fprintf(pout, "(Completed in %s)\n",
			bres.Time_completed.Sub(bres.Time_submitted))
		// fmt.Fprintf(pout, "<h3>Modified</h2> %s\n", uitime(bres.Time_modified))

		fmt.Fprintf(bout, "<h3>SCM</h2> <a href=\"%s\">%s</a>\n",
			uiscm(bres.SCMURL), uiscm(bres.SCMURL))
		fmt.Fprintf(pout, "<h3>SCM</h2> <a href=\"%s\">%s</a>\n",
			uiscm(bres.SCMURL), uiscm(bres.SCMURL))

		if pbres != nil {
			s_bres_rpms := iter_rpms(bres.Tasks.Rpms)

			count := 0
			for _, name := range s_bres_rpms {
				orpm, found := pbres.Tasks.Rpms[name]
				rpm := bres.Tasks.Rpms[name]
				if !found {
					continue
				}
				if orpm.NVR != rpm.NVR {
					continue
				}
				count++
			}
			if count > 0 {
				fmt.Fprintf(pout, "<h3>Unchanged rpms </h2><pre>%d</pre>",
					count)
			}

			var done bool
			done = false
			for _, name := range s_bres_rpms {
				_, found := pbres.Tasks.Rpms[name]
				rpm := bres.Tasks.Rpms[name]
				if found {
					continue
				}

				if !done {
					fmt.Fprintf(pout, "<h3>New rpms </h2> <ul>")
					done = true
				}
				prnt_rpm_html(pout, rpm)
			}
			if done {
				fmt.Fprintf(pout, "</ul>")
			}
			done = false
			for _, name := range s_bres_rpms {
				orpm, found := pbres.Tasks.Rpms[name]
				rpm := bres.Tasks.Rpms[name]
				if !found {
					continue
				}
				if orpm.NVR == rpm.NVR {
					continue
				}

				if !done {
					fmt.Fprintf(pout, "<h3>Changed rpms </h2> <ul>")
					done = true
				}

				prnt_rpm_html(pout, orpm)
				if false && orpm.State == 1 && rpm.State == 1 {
					prefix := fmt.Sprintf("%*s", len(name), "")
					oVR := strings.Split(orpm.NVR, "-")
					nVR := strings.Split(rpm.NVR, "-")
					if oVR[len(oVR)-2] == nVR[len(nVR)-2] {
						fmt.Printf("<li>  %s %*s %s\n", prefix,
							len(nVR[len(nVR)-2]), "", nVR[len(nVR)-1])
					} else {
						fmt.Printf("<li>  %s %s-%s\n", prefix,
							nVR[len(nVR)-2], nVR[len(nVR)-1])
					}
				} else {
					prnt_rpm_html(pout, rpm)
				}
			}
			if done {
				fmt.Fprintf(pout, "</ul>")
			}

			done = false
			for _, name := range iter_rpms(pbres.Tasks.Rpms) {
				_, found := bres.Tasks.Rpms[name]
				orpm := pbres.Tasks.Rpms[name]
				if found {
					continue
				}

				if !done {
					fmt.Fprintf(pout, "<h3>REMOVED rpms </h2> <ul>")
					done = true
				}

				prnt_rpm_html(pout, orpm)
			}
			if done {
				fmt.Fprintf(pout, "</ul>")
			}

			fmt.Fprintf(pout, "<h3>GIT log</h2><pre>%s</pre> </h2>",
				html.EscapeString(build_diff(pbres, bres)))

		} else {
			fmt.Fprintf(pout, "<h3>Rpms </h2> <ul>")

			for _, name := range iter_rpms(bres.Tasks.Rpms) {
				rpm := bres.Tasks.Rpms[name]
				prnt_rpm_html(pout, rpm)
			}
			fmt.Fprintf(pout, "</ul>")
		}
		fmt.Fprintf(bout, "<h3>Rpms </h2> <ul>")

		for _, name := range iter_rpms(bres.Tasks.Rpms) {
			rpm := bres.Tasks.Rpms[name]
			prnt_rpm_html(bout, rpm)
		}
		fmt.Fprintf(bout, "</ul>")

		fmt.Fprintf(bout, "</body>")
		fmt.Fprintf(bout, "</body>")

		bout.Close()
		pout.Close()
	}

	fmt.Fprintf(sum, "</table></body>")
	fmt.Fprintf(full, "</table></body>")

	sum.Close()
	full.Close()
}

// Item build items you get from MBSAPI
type Item struct {
	ID    int
	State int
}

// MBSAPI Main JSON data from MBS
type MBSAPI struct {
	Items []Item
	Meta  struct {
		First    string
		Last     string
		Next     string
		Page     int
		Pages    int
		Per_page int
		Total    int
	}
}

func builds(url string) *MBSAPI {

	// fmt.Println("JDBG:", url)
	resp, err := http.Get(url)
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	body, err := ioutil.ReadAll(resp.Body)

	var tres MBSAPI
	err = json.Unmarshal(body, &tres)
	if err != nil {
		fmt.Println("error:", err)
	}
	return &tres
}

// Rpm Source NVR that was built, and link to task that built it.
type Rpm struct {
	NVR          string
	State        int
	State_reason string
	Task_id      int
}

// Build MBS module build entry, goes from modulemd and owner/etc. data to rpms and other output.
type Build struct {
	ID      int
	Name    string
	Stream  string
	Version string

	ModuleMD string

	Owner  string
	SCMURL string

	Component_builds []int

	State        int
	State_name   string
	State_reason string

	Tasks struct {
		Rpms map[string]Rpm
	}

	Time_completed time.Time
	Time_modified  time.Time
	Time_submitted time.Time
}

func build(bid int) *Build {

	usr, err := user.Current()
	var body []byte
	var path string
	var cached bool

	if err == nil && usr.HomeDir != "" {
		path = fmt.Sprintf("%s/ID/%d", buildCachePath(usr), bid)
		file, err := os.Open(path) // Should timeout?
		if err == nil {
			defer file.Close()
			fi, err := file.Stat()
			if err == nil && time.Since(fi.ModTime()) <= cacheIDTime {
				body, err = ioutil.ReadAll(file)
				if err == nil {
					cached = true
				}
			}
		}
	}

	if !cached {
		url := MBSURL()
		url += fmt.Sprintf("%d?verbose=1", bid)
		found := false
		for i := 0; i < 4; i++ {
			resp, err := http.Get(url)
			if err == nil {
				found = true
				defer resp.Body.Close()
				body, err = ioutil.ReadAll(resp.Body)
				break
			}
			// FIXME: Check it's a timeout or whatever?
		}
		if !found {
			return nil
		}
	}

	if !cached && path != "" {
		go func() {
			os.MkdirAll(filepath.Dir(path), os.ModePerm)
			file, err := os.Create(path) // Should timeout?
			if err == nil {
				r := bytes.NewReader(body)
				if _, err := io.Copy(file, r); err != nil {
					// FIXME: rename
				}
			}
		}()
	}

	var bres Build
	err = json.Unmarshal(body, &bres)
	if err != nil {
		fmt.Println("error:", err)
	}
	// fmt.Printf("%+v", bres)
	return &bres
}
