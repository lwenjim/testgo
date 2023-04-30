package main

import (
	"context"
	"fmt"
	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/cache"
	"testing"

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

func TestSss(t *testing.T) {
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
