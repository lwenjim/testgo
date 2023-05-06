package main

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"strings"
	"testing"

	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/cache"

	"github.com/peterhellberg/giphy"
	v1 "k8s.io/api/core/v1"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/kubectl/pkg/scheme"
)

func TestMain(m *testing.M) {
	m.Run()
}

func Test_aa(t *testing.T) {
	g := giphy.DefaultClient
	g.APIKey = "xVXd8j7UxP8Lvn8Dn1aLjLAd5EHYGE31"
	g.Rating = "pg-13"
	g.Limit = 30 * 2
	trendings, _ := g.Search([]string{"11"})
	for _, trending := range trendings.Data {
		fmt.Println(trending.MediaURL())
	}
}

func TestClientSet(t *testing.T) {

}

func TestRestfullClient(t *testing.T) {
	config, err := clientcmd.BuildConfigFromFlags("", clientcmd.RecommendedHomeFile)
	println(clientcmd.RecommendedHomeFile)
	if err != nil {
		panic(err)
	}
	config.GroupVersion = &v1.SchemeGroupVersion
	config.NegotiatedSerializer = scheme.Codecs
	config.APIPath = "/api"

	restClient, err := rest.RESTClientFor(config)
	if err != nil {
		panic(err)
	}
	pod := v1.Pod{}
	err = restClient.Get().Namespace("default").Resource("pods").Name("bar-app").Do(context.TODO()).Into(&pod)
	if err != nil {
		println(err)
	} else {
		println(pod.Name)
	}
}

func TestSharedInformerFactory(t *testing.T) {
	config, err := clientcmd.BuildConfigFromFlags("", clientcmd.RecommendedHomeFile)
	if err != nil {
		panic(err)
	}
	clientSet, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err)
	}

	factory := informers.NewSharedInformerFactoryWithOptions(clientSet, 0, informers.WithNamespace("default"))
	informer := factory.Core().V1().Pods().Informer()

	_, err = informer.AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: func(obj interface{}) {
			fmt.Println("Add Event")
		},
		UpdateFunc: func(oldObj, newObj interface{}) {
			fmt.Println("Update Event")
		},
		DeleteFunc: func(obj interface{}) {
			fmt.Println("Delete Event")
		},
	})
	if err != nil {
		panic(err)
	}

	stopCh := make(chan struct{})
	factory.Start(stopCh)
	factory.WaitForCacheSync(stopCh)
	<-stopCh
}

func TestEventHandler(t *testing.T) {

}

func TestGeneralSql(t *testing.T) {
	lMap := map[string]uint8{
		"短信":   0,
		"电话铃声": 1,
	}
	path := "/Users/jim/Library/Application Support/jspp/4185955/message/834c38e419a387453405f67c1373d052c9a13902/file/75688595411f66de667cb8a4560ca1cc18b40b1a/铃声-2/"
	for key, val := range lMap {

		dirEntries, err := os.ReadDir(path + key)
		if err != nil {
			return
		}
		var values []string
		for _, entry := range dirEntries {
			split := strings.Split(entry.Name(), "-")
			remoteUrl := "https://jspp-dev.oss-cn-shanghai.aliyuncs.com/phonesound/%E9%93%83%E5%A3%B0-2/%E7%94%B5%E8%AF%9D%E9%93%83%E5%A3%B0/" + url.QueryEscape(entry.Name())
			values = append(values, fmt.Sprintf("INSERT INTO `jspp`.`t_push_phone_sound` (`name`, `url`, `sound_type`, `channel_type`) VALUES ('%s', '%s', %d, %d);", split[0], remoteUrl, val, 1))
		}
		println(strings.Join(values, "\n"))
	}
}
