# ARQUITECTURA — Variante C (catalogo-app)

Respuestas de arquitectura de la entrega final. Recorre las preguntas obligatorias del curso, la pregunta propia de la variante C, dos dificultades de MongoDB y lo que falta para llevar este despliegue a producción. 

---

## 1) Preguntas obligatorias del curso

### a) ¿Por qué el frontend se configura con `API_HOST` en tiempo de ejecución y no con `VITE_API_URL` en tiempo de construcción? Si fuera al revés, ¿qué habría que rehacer para pasar de desarrollo a producción?

Se configura con `API_HOST` porque su valor se define al arrancar el contenedor, por lo que la misma imagen del frontend se puede utilizar en cualquier entorno. En cambio con `VITE_API_URL` la dirección del backend quedaría fija al construir la imagen.

El frontend usa rutas relativas para las peticiones HTTP para comunicarse con la API del backend. Esas rutas se definen en `frontend/src/api.js` (`/api/...`). Por eso, al construir la imagen, Vite no escribe la dirección del backend en los archivos estáticos del frontend.
La dirección del backend recién se define en tiempo de ejecución. Al arrancar el contenedor del frontend, nginx toma los valores de `API_HOST` y `API_PORT` y construye la dirección del backend a la que reenvía las peticiones. Así la imagen del frontend queda independiente de la dirección concreta del backend.

Si se usara la variable de entorno `VITE_API_URL`, durante la construcción de la imagen Vite copiaría ese valor en los archivos estáticos del frontend. La URL base de la API quedaría fija dentro de la imagen, ligada a la dirección del backend que se hubiera definido en ese momento. Por lo cual cada entorno (local, producción u otro) exigiría reconstruir la imagen del frontend con una `VITE_API_URL` distinta, o mantener varias imágenes etiquetadas por entorno.

---

### b) ¿Por qué esta arquitectura no necesita CORS? ¿Qué habría que agregar si la aplicación de página única se comunicara directamente con la API?

El navegador aplica CORS cuando JavaScript realiza una petición HTTP a un recurso de un origen diferente al de la página actual. Dos orígenes son diferentes si cambia el protocolo, host (dominio/IP) o puerto. Si los tres coinciden, se considera **same-origin** y no se requiere CORS para esa petición.

En esta arquitectura la API se consume a través del mismo host y puerto que la aplicación web: Compose (`http://localhost:3000`), Ingress (`http://catalogo.local`) o NodePort (`http://<IP-del-nodo>:30302`). En el archivo del frontend en donde se definen las peticiones al backend (`frontend/src/api.js`) la base de la URL destino es la ruta relativa `/api`. Entonces, al realizar una petición HTTP (`fetch("/api/productos")`), el navegador la resuelve con el mismo protocolo, host y puerto (por ejemplo `http://localhost:3000/api/productos`). Los tres coinciden: es **same-origin** y no se requiere CORS.

Nginx recibe la petición y la reenvía al backend (`API_HOST`, `API_PORT`). El navegador no hace esa segunda petición: la URL que utiliza sigue siendo la del frontend. FastAPI no incluye `CORSMiddleware` porque no hay un origen distinto que autorizar.

Si la SPA se comunicara directamente con la API, JavaScript usaría una URL absoluta hacia la API publicada. Por ejemplo, `http://<IP-del-nodo>:30502/productos` y la página seguiría en `http://catalogo.local` o en `http://<IP-del-nodo>:30302`. Por lo que cambia el host o el puerto, así que es otro origen y el navegador exige cabeceras CORS en la respuesta (`Access-Control-Allow-Origin`, etc.). En FastAPI esas cabeceras se agregan con `CORSMiddleware`, indicando el origen permitido de la página y los métodos y cabeceras admitidos. Sin esas cabeceras, el script no puede leer la respuesta aunque el servidor HTTP responda.

---

### c) ¿Por qué hay un solo autoescalador entre los doce objetos? ¿Qué ocurriría si se le asignara uno a catalogo-db? ¿Y por qué tampoco lo tiene el frontend?

Hay un solo HPA porque, de los doce objetos, el único que conviene multiplicar bajo carga HTTP es `catalogo-api`. El uso de CPU del backend sube con la cantidad de peticiones (la memoria también puede subir, pero el HPA de este proyecto solo mide CPU). Agregar réplicas dinámicamente reparte esas peticiones: cada réplica hace menos trabajo y el conjunto atiende más. El uso total de CPU del Deployment suele subir, porque hay más Pods pero el uso de CPU de cada réplica baja. Además, como es una API sin estado —el servidor no necesita recordar información de una petición anterior para procesar la siguiente—, cada réplica puede atender cualquier petición entrante: las réplicas son intercambiables. 

`catalogo-db` no se puede escalar con un HPA. Si se le asignara uno, Kubernetes intentaría crear más de un Pod. El Pod de la base de datos solicita un PVC (`catalogo-db-pvc`): un PersistentVolumeClaim, el pedido de un disco persistente. Ese volumen está en `ReadWriteOnce` y va montado en `/data/db`. Un segundo Pod solicitaría el mismo volumen, no podría montarlo y quedaría pendiente. El Deployment de `catalogo-db` arranca un solo proceso `mongod` y los archivos de la base están en ese disco.

El frontend también se podría escalar porque es una aplicación sin estado. Nginx sirve archivos estáticos y también reenvía `/api/` a `catalogo-api`. El servir esos archivos y el reenvío requieren poco uso de CPU en comparación con el uso del backend. Bajo alta carga el frontend no suele tener una subida de uso considerable, así que escalarlo a más réplicas es innecesario.

---

## 2) Pregunta propia de la variante C: ¿qué deja de estar garantizado al pasar de una réplica de la API a tres?

Con **una** réplica de `catalogo-api`, un archivo escrito en el filesystem del contenedor (por ejemplo `/tmp/imagen-test.png`) es local a ese Pod, es decir solo existe en ese contenedor. Con **varias** réplicas:

- Ninguna otra réplica ve ese archivo: no está en su filesystem.
- Al **recrear** el Pod, el contenido del disco efímero del contenedor **desaparece**, así que el archivo deja de existir.

Por eso en esta variante las **imágenes de producto** se guardan en el documento del producto en MongoDB, en el campo `imagen_datos`, no en rutas compartidas entre Pods. La API no mantiene estado en disco: el catálogo compartido es la base de datos vía Service `catalogo-db`.

Un carrito guardado en la sesión del servidor tampoco sobreviviría. Esa sesión vive en la memoria del Pod que atendió el alta. Con varias réplicas, la petición siguiente puede caer en otra: esa réplica no tiene la sesión y el carrito se pierde.

La prueba de que un archivo del disco de un Pod no existe en la otra réplica está en la [sección 5 de INFORME.md](INFORME.md#5-disco-local-del-pod-no-compartido-entre-réplicas).


---

## 3) Dos dificultades propias de MongoDB (durante el curso)

### Dificultad 1 — `authSource=admin` en la URI

Esta dificultad se manifestó al iniciar el contenedor de la API `catalogo-api`, que arrojaba el error `Authentication failed` aunque se utilizaban las credenciales correctas y el contenedor de MongoDB ya estaba levantado. El error sucedía porque el usuario creado con `MONGO_INITDB_ROOT_*` vive en la base `admin`. La API se conecta a MongoDB usando una URI armada así: `mongodb://catalogo_user:catalogo_pass@catalogo-db:27017/catalogodb?authSource=admin`, donde `catalogodb` es el nombre de la base de datos de los productos. La sección `authSource=admin` indica que el usuario con el que se intenta autenticar está en la base de datos `admin`. Si ese parámetro se omite al crear la URI, MongoDB busca el usuario en `catalogodb` ya que es la base a la cual se intenta conectar. Sin `authSource`, se busca en esa base de datos al usuario. Al no encontrarlo en `catalogodb`, falla la autenticación.

Se logró diagnosticar con los logs de la API (pymongo): la misma URI con `?authSource=admin` se conecta y, sin ese parámetro, MongoDB responde `Authentication failed`. Se resolvió armando la URI con `authSource=admin`, sin omitir ese parámetro. `backend/main.py` toma el host, el puerto y el nombre de la base (`DB_HOST`, `DB_PORT`, `DB_NAME`) del ConfigMap, y el usuario y la contraseña (`DB_USER`, `DB_PASSWORD`) del Secret, y agrega `?authSource=admin`.

### Dificultad 2 — healthcheck responda bien aunque no se pueda conectar a db

Esta dificultad se manifestó con `catalogo-db` en estado `healthy` y, al mismo tiempo, la API fallando con `Authentication failed`.

Este error sucede porque el healthcheck de MongoDB solo comprueba que el proceso acepte conexiones utilizando `db.adminCommand('ping')`, el cual no requiere autenticación. Es decir, el healthcheck no verifica la autenticación: eso se hace recién cuando la API intenta conectarse.

Un caso frecuente fue cambiar `MONGO_INITDB_ROOT_PASSWORD` en `docker-compose.yml` cuando el volumen `catalogo-db-data` ya tenía datos. Esas variables `MONGO_INITDB_*` se aplican **solo** sobre un volumen vacío. MongoDB arrancó con el usuario y la contraseña anteriores, el ping del healthcheck respondió correctamente, Compose declaró el servicio `healthy` y la API, al autenticarse con la contraseña nueva, falló.

El estado `healthy` de MongoDB no se toma como prueba de que la API puede autenticarse. Prueba que el proceso acepta conexiones y que el servicio de MongoDB está funcional. 

---

## 4) Pendiente para un entorno de producción real

**Observabilidad.** Para ver qué ocurre en el clúster actualmente hay que consultar cada Pod. 
- `kubectl top` para mostrar estadísticas de CPU y memoria que ese Pod está usando en ese momento (datos con los que el HPA decide si suma réplicas). 
- `kubectl logs` para mostrar la salida de logs del contenedor (errores de la API, el ping a MongoDB, un request que falló, etc) 

Esas dos consultas alcanzan para el laboratorio. En producción hacen falta tres cosas que este despliegue no tiene: métricas guardadas en el tiempo, logs de todos los Pods en un solo lugar, y trazas de cada petición.

- Las métricas son valores numéricos guardados en el tiempo que permiten medir el comportamiento y rendimiento de CPU, memoria y latencia de cada servicio. Con esa historia se puede alertar por ejemplo si el HPA llegó al máximo de réplicas o si la API dejó de responder.
- Los logs de todos los Pods tienen que centralizarse en un solo lugar, usando herramientas como Loki o EFK, así es mucho más fácil buscar un error sin tener que acceder a cada Pod.
- Una traza permite seguir el recorrido de una petición a través de diferentes servicios y el tiempo que tardó en cada uno.

Se podría utilizar Kubernetes Dashboard que es una interfaz web para mirar objetos y consumo. Sirve para inspeccionar. El monitoreo de producción se construye con Prometheus, que reúne las métricas, y Grafana, que se encarga de graficarlas.

**CI/CD.** En el curso cada paso se ejecutó a mano. `docker build` arma la imagen, `docker push` la sube al registry y `helm upgrade` la despliega en el clúster. Un pipeline hace esa misma cadena cuando entra un commit o un tag al repositorio: construye, corre las pruebas, publica la imagen y actualiza el release, sin que alguien escriba los comandos. Las herramientas habituales son GitHub Actions, GitLab CI, Jenkins y Argo CD. Este repositorio no tiene un pipeline: el deploy sigue siendo el `helm upgrade` corrido a mano.

**Secretos.** La contraseña de MongoDB (`catalogo_user` / `catalogo_pass`) está escrita en el Secret y en el chart, y esos archivos están en el repositorio. Alcanza para el laboratorio, donde la contraseña es pública a propósito. En producción esa contraseña la entrega un gestor (Vault o el KMS del cloud) o un controlador que la inyecta en el clúster (Sealed Secrets o External Secrets). El repositorio guarda la referencia, no el valor.

**Backups.** Los productos viven en el disco de `catalogo-db`. Si ese volumen se pierde, el catálogo se pierde con él: no hay otra copia. En producción haría falta un respaldo periódico de MongoDB y, además, haber probado que esa copia se puede restaurar. En Kubernetes ese respaldo es un CronJob: a la hora programada levanta un Pod, corre el dump y el Pod termina. Este chart no define ese CronJob.

**MongoDB.** `catalogo-db` es un Deployment de una sola réplica. El disco es un PVC `ReadWriteOnce` montado en `/data/db`, así que ese volumen queda atado a un solo Pod. Si el nodo cae, no queda otro proceso `mongod` que siga aceptando escrituras: no hay failover, y los datos no están respaldados en otro lado. En producción MongoDB se corre como replica set: varios procesos `mongod` con los mismos datos. Uno de ellos es el nodo primario, el único que acepta escrituras. Los otros son nodos secundarios: copian lo que escribió el primario y, si ese cae, el conjunto elige a otro como primario. El objeto de Kubernetes para eso es un StatefulSet: cada réplica tiene nombre estable y su propio disco. Un Deployment sirve para réplicas intercambiables y sin estado, como `catalogo-api`. La base no es ese caso, y el StatefulSet no se vio en este curso.

