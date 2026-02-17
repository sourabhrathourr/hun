package daemon

import (
	"fmt"
	"sync"
	"time"
)

// Subscriber receives log lines for specific project/service combinations.
type Subscriber struct {
	ID      int
	Project string
	Service string // empty means all services
	Ch      chan LogLine
	dropped int
}

// SubscriberManager manages log subscribers.
type SubscriberManager struct {
	subscribers map[int]*Subscriber
	nextID      int
	mu          sync.RWMutex
}

// NewSubscriberManager creates a new subscriber manager.
func NewSubscriberManager() *SubscriberManager {
	return &SubscriberManager{
		subscribers: make(map[int]*Subscriber),
	}
}

// Subscribe creates a new subscriber for the given project/service.
func (sm *SubscriberManager) Subscribe(project, service string) *Subscriber {
	sm.mu.Lock()
	defer sm.mu.Unlock()
	sm.nextID++
	sub := &Subscriber{
		ID:      sm.nextID,
		Project: project,
		Service: service,
		Ch:      make(chan LogLine, 256),
	}
	sm.subscribers[sub.ID] = sub
	return sub
}

// Unsubscribe removes a subscriber.
func (sm *SubscriberManager) Unsubscribe(id int) {
	sm.mu.Lock()
	defer sm.mu.Unlock()
	if sub, ok := sm.subscribers[id]; ok {
		close(sub.Ch)
		delete(sm.subscribers, id)
	}
}

// Broadcast sends a log line to all matching subscribers.
func (sm *SubscriberManager) Broadcast(line LogLine) {
	sm.mu.Lock()
	defer sm.mu.Unlock()
	for _, sub := range sm.subscribers {
		if sub.Project != line.Project {
			continue
		}
		if sub.Service != "" && sub.Service != line.Service {
			continue
		}

		if sub.dropped > 0 {
			warn := LogLine{
				Timestamp: time.Now(),
				Project:   line.Project,
				Service:   line.Service,
				IsErr:     true,
				Text:      fmt.Sprintf("hun: dropped %d log lines due to slow subscriber", sub.dropped),
			}
			select {
			case sub.Ch <- warn:
				sub.dropped = 0
			default:
				sub.dropped++
				continue
			}
		}

		select {
		case sub.Ch <- line:
		default:
			sub.dropped++
		}
	}
}
