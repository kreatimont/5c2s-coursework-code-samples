This are data classes – heart of app.

    * TransportDataProvider – protocol that describes how presentation layer communicates with data layer.
    * LvivGTFSTransportDataProvider – example implementation of protocol above. 
      This class performs a number of managment tasks, such as: fetching data,
      caching, data processing. One class responsible for one one city, in our sample – Lviv.
