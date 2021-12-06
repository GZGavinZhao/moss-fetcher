/*
 * This file is part of moss-fetcher.
 *
 * Copyright © 2020-2021 Serpent OS Developers
 *
 * This software is provided 'as-is', without any express or implied
 * warranty. In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 */

module moss.fetcher;

import etc.c.curl;
import moss.fetcher.queue;
import moss.fetcher.worker;
import std.parallelism : totalCPUs;

public import moss.core.fetchcontext;

/**
 * A fairly simple implementation of the FetchContext. Downloads added to
 * this fetcher are subject to sorting by *expected size* and grouped by
 * their URI.
 *
 * The largest pending downloads will typically download on the main thread
 * while the remaining threads will gobble up all the small jobs, hopefully
 * leading to better distribution.
 *
 * In a lame attempt at optimisation we support connection reuse as well as
 * sharing the shmem cache between curl handles (CURLSH)
 */
public final class Fetcher : FetchContext
{
    /**
     * Construct a new Fetcher with the given number of worker thread
     */
    this(uint nWorkers = totalCPUs() - 1)
    {
        /* Ensure we always have at LEAST 1 worker */
        if (nWorkers < 1)
        {
            nWorkers = 1;
        }

        this.nWorkers = nWorkers;
        shmem = curl_share_init();
        queue = new FetchQueue();

        /* Create N workers, worker 0 preferring large items first */
        foreach (i; 0 .. nWorkers)
        {
            auto pref = i == 0 ? WorkerPreference.LargeItems : WorkerPreference.SmallItems;
            workers[i] = new FetchWorker(shmem, pref);
        }
    }

    /**
     * Enqueue a fetchable for future processing
     */
    override void enqueue(in Fetchable f)
    {
        queue.enqueue(f);
    }

    /**
     * For every download currently enqueued, process them all and
     * return from this function when done.
     */
    override void fetch()
    {

    }

    /**
     * Close this fetcher and any associated resources
     */
    void close()
    {
        if (shmem is null)
        {
            return;
        }

        /* Destroy our workers */
        foreach (ref worker; workers)
        {
            worker.close();
            worker.destroy();
        }
        workers = null;

        /* Destroy curl share */
        curl_share_cleanup(shmem);
        shmem = null;
    }

private:

    CURLSH* shmem = null;
    uint nWorkers = 0;
    FetchQueue queue = null;
    FetchWorker[] workers;
}
