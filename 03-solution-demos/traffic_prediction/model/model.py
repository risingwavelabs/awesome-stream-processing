import tensorflow as tf
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from tensorflow.keras.layers import Dense,LSTM,Dropout
from sklearn.preprocessing import MinMaxScaler
from sklearn.metrics import mean_squared_error, mean_absolute_error
import math

def load_data(dataset):
    f = pd.read_csv(dataset)

    data = pd.DataFrame()
    data['total_flow'] = f['Total Flow']
    data['speed'] = f['Avg Speed']

    data['total_flow'] = np.array(data['total_flow']).astype(np.float64)
    data['speed'] = np.array(data['speed']).astype(np.float64)

    return data

# train data  2025.5.21-2025.5.27
train_set = load_data('train_data.csv')
# test data  2025.5.28
test_set = load_data('test_data.csv')

# normalization
sc = MinMaxScaler(feature_range=(0, 1))
train_set_sc = sc.fit_transform(train_set)
test_set_sc = sc.transform(test_set)


# dividing time steps
time_step = 5
features = 2
x_train = []
y_train = []
x_test = []
y_test = []
for i in range(time_step, len(train_set_sc)):
    x_train.append(train_set_sc[i - time_step:i])
    y_train.append(train_set_sc[i, 0]) # 只预测total_flow
for i in range(time_step, len(test_set_sc)):
    x_test.append(test_set_sc[i - time_step:i])
    y_test.append(test_set_sc[i, 0])
x_test, y_test = np.array(x_test), np.array(y_test)

# transfer to a numpy array
x_train, y_train = np.array(x_train), np.array(y_train).reshape(-1, 1)
x_test, y_test = np.array(x_test), np.array(y_test).reshape(-1, 1)
x_train = np.reshape(x_train, (x_train.shape[0], time_step, features))
x_test = np.reshape(x_test, (x_test.shape[0], time_step, features))


# Tensorflow Model (2 LSTM, 2 Dropout, 1 Dense)
model = tf.keras.Sequential([
    LSTM(80, return_sequences=True),
    Dropout(0.2),
    LSTM(80),
    Dropout(0.2),
    Dense(1)
])
model.compile(optimizer='adam',
              loss='mse',)


history = model.fit(x_train, y_train,
                    epochs=time_step,
                    validation_data=(x_test, y_test))

pre_flow = model.predict(x_test)

# denormalization
def inv_transform_only_flow(arr):
    arr_full = np.zeros((arr.shape[0], features))
    arr_full[:, 0] = arr[:, 0]
    return sc.inverse_transform(arr_full)[:, 0]

pre_flow = inv_transform_only_flow(pre_flow)
real_flow = inv_transform_only_flow(y_test)

# calculate error
mse = mean_squared_error(pre_flow, real_flow)
rmse = math.sqrt(mean_squared_error(pre_flow, real_flow))
mae = mean_absolute_error(pre_flow, real_flow)
print('Mean Square Error---', mse)
print('Root Mean Square Error---', rmse)
print('Mean Absolute Error---', mae)

plt.figure(figsize=(15,10))
plt.plot(real_flow, label='Real_Flow', color='r', )
plt.plot(pre_flow, label='Pre_Flow')
plt.legend()
plt.show()

model.save('traffic_prediction_model.keras')
